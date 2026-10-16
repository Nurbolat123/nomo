import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nomo_core/nomo_core.dart';

import 'location_service.dart';

class DriverState {
  const DriverState({
    this.profile,
    this.offer,
    this.order,
    this.position,
    this.heading = 0,
    this.demand = const [],
    this.earnings,
    this.notice,
    this.approach = const [],
    this.tripRoute = const [],
    this.remainingM,
  });

  final DriverProfile? profile;
  final Offer? offer;
  final Order? order;
  final LatLng? position;
  final double heading;
  final List<DemandCell> demand;
  final Earnings? earnings;

  /// One-off message for the UI (e.g. "passenger cancelled").
  final String? notice;

  /// Road route from the driver to the pickup.
  final List<LatLng> approach;

  /// Road route from the pickup (or the driver, once rerouted) to the destination.
  final List<LatLng> tripRoute;

  /// Meters left on the current route (from the map).
  final double? remainingM;

  /// Route for the map at the current stage.
  List<LatLng> get activeRoute {
    final o = order;
    if (o == null) return offer == null ? const [] : RouteMath.decode(offer!.route);
    switch (o.status) {
      case OrderStatus.assigned:
        return approach;
      case OrderStatus.arrived:
      case OrderStatus.inProgress:
        return tripRoute;
      default:
        return const [];
    }
  }

  bool get online => profile?.online == true;

  DriverState copyWith({
    DriverProfile? profile,
    Offer? offer,
    bool clearOffer = false,
    Order? order,
    bool clearOrder = false,
    LatLng? position,
    double? heading,
    List<DemandCell>? demand,
    Earnings? earnings,
    String? notice,
    bool clearNotice = false,
    List<LatLng>? approach,
    List<LatLng>? tripRoute,
    double? remainingM,
  }) =>
      DriverState(
        profile: profile ?? this.profile,
        offer: clearOffer ? null : offer ?? this.offer,
        order: clearOrder ? null : order ?? this.order,
        position: position ?? this.position,
        heading: heading ?? this.heading,
        demand: demand ?? this.demand,
        earnings: earnings ?? this.earnings,
        notice: clearNotice ? null : notice ?? this.notice,
        approach: clearOrder ? const [] : approach ?? this.approach,
        tripRoute: clearOrder ? const [] : tripRoute ?? this.tripRoute,
        remainingM: clearOrder ? null : remainingM ?? this.remainingM,
      );
}

class DriverController extends Notifier<DriverState> {
  final _location = LocationService();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _poll;
  DateTime _lastHttpLocation = DateTime.fromMillisecondsSinceEpoch(0);

  ApiClient get _api => ref.read(apiProvider);

  @override
  DriverState build() {
    final rt = ref.read(realtimeProvider);
    _subs
      ..add(rt.on('offer.new').listen((e) {
        if (state.order?.isActive == true) return;
        state = state.copyWith(offer: Offer.fromJson(e.data as Map<String, dynamic>));
      }))
      ..add(rt.on('offer.cancelled').listen((e) {
        if ((e.data as Map)['order_id'] == state.offer?.orderId) state = state.copyWith(clearOffer: true);
      }))
      ..add(rt.on('order.updated').listen((e) => _onOrder(Order.fromJson(e.data as Map<String, dynamic>))))
      ..add(rt.on('driver.status').listen((e) {
        state = state.copyWith(profile: DriverProfile.fromJson(e.data as Map<String, dynamic>));
      }))
      ..add(rt.connection.where((c) => c).listen((_) => refresh()))
      ..add(_location.positions.listen(_onPosition));
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _poll?.cancel();
      _location.stop();
    });
    return const DriverState();
  }

  Future<void> init() async {
    await refresh();
    final p = await LocationService.current();
    if (p != null) state = state.copyWith(position: LatLng(p.latitude, p.longitude));
    if (state.online || state.order?.isActive == true) _startTracking();
    unawaited(loadEarnings());
    unawaited(loadDemand());
  }

  Future<void> refresh() async {
    try {
      final profile = await _api.driverProfile();
      state = state.copyWith(profile: profile);
      if (!profile.approved) return;
      final order = await _api.driverActiveOrder();
      if (order != null) {
        state = state.copyWith(order: order, clearOffer: true);
        unawaited(buildRoute());
      } else if (state.order?.isActive == true) {
        state = state.copyWith(clearOrder: true);
      }
      if (state.order == null) {
        final offer = await _api.currentOffer();
        state = offer == null ? state.copyWith(clearOffer: true) : state.copyWith(offer: offer);
      }
    } catch (_) {}
  }

  Future<void> reloadProfile() async {
    state = state.copyWith(profile: await _api.driverProfile());
  }

  void _startTracking() => _location.start(title: 'Nomo Driver', text: 'Вы на линии — получаете заказы');

  Future<void> goOnline() async {
    if (!await LocationService.ensurePermission()) {
      throw ApiException('Разрешите доступ к геолокации в настройках телефона');
    }
    final p = await LocationService.current();
    final profile = await _api.setOnline(true, lat: p?.latitude, lng: p?.longitude);
    state = state.copyWith(profile: profile, position: p == null ? null : LatLng(p.latitude, p.longitude));
    _startTracking();
    unawaited(loadDemand());
  }

  Future<void> goOffline() async {
    final profile = await _api.setOnline(false);
    state = state.copyWith(profile: profile, clearOffer: true);
    if (state.order?.isActive != true) _location.stop();
  }

  Future<void> accept() async {
    final offer = state.offer;
    if (offer == null) return;
    try {
      final o = await _api.acceptOffer(offer.orderId);
      state = state.copyWith(order: o, clearOffer: true);
      unawaited(buildRoute());
    } catch (e) {
      state = state.copyWith(clearOffer: true);
      rethrow;
    }
  }

  Future<void> decline() async {
    final offer = state.offer;
    state = state.copyWith(clearOffer: true);
    if (offer != null) await _api.declineOffer(offer.orderId);
  }

  void offerExpired(String orderId) {
    if (state.offer?.orderId == orderId) state = state.copyWith(clearOffer: true);
  }

  Future<void> arrived() async {
    state = state.copyWith(order: await _api.driverArrived(state.order!.id));
    unawaited(buildRoute());
  }

  Future<void> startTrip() async {
    state = state.copyWith(order: await _api.driverStart(state.order!.id));
    unawaited(buildRoute());
  }

  Future<void> complete() async {
    final o = await _api.driverComplete(state.order!.id);
    state = state.copyWith(order: o);
    if (!state.online) _location.stop();
    unawaited(loadEarnings());
  }

  Future<void> cancelTrip() async {
    await _api.driverCancel(state.order!.id);
    state = state.copyWith(clearOrder: true);
  }

  Future<void> ratePassenger(int stars) async {
    final o = state.order;
    if (o == null) return;
    try {
      await _api.ratePassenger(o.id, stars);
    } finally {
      closeTrip();
    }
  }

  void closeTrip() => state = state.copyWith(clearOrder: true);
  void clearNotice() => state = state.copyWith(clearNotice: true);

  Future<void> loadEarnings() async {
    try {
      state = state.copyWith(earnings: await _api.earnings());
    } catch (_) {}
  }

  Future<void> loadDemand() async {
    try {
      state = state.copyWith(demand: await _api.demand());
    } catch (_) {}
  }

  bool _routing = false;
  String? _routedFor;

  /// Builds the road route for the current stage: to the pickup while
  /// assigned, to the destination after pickup. [force] rebuilds from the
  /// driver's position (used when the map says the car left the route).
  Future<void> buildRoute({bool force = false}) async {
    final o = state.order, me = state.position;
    if (o == null || _routing) return;
    final stage = '${o.id}:${o.status.name}';
    if (!force && _routedFor == stage) return;
    _routing = true;
    try {
      final svc = ref.read(routeServiceProvider);
      final pickup = LatLng(o.from.lat, o.from.lng), dest = LatLng(o.to.lat, o.to.lng);
      if (o.status == OrderStatus.assigned) {
        if (me == null) return;
        final r = await svc.drive(me, pickup);
        if (r != null && state.order?.id == o.id) state = state.copyWith(approach: r.points);
      } else if (o.status == OrderStatus.arrived || o.status == OrderStatus.inProgress) {
        final saved = RouteMath.decode(o.route);
        if (!force && saved.length >= 2) {
          state = state.copyWith(tripRoute: saved);
        } else {
          final from = force && me != null ? me : pickup;
          final r = await svc.drive(from, dest);
          if (r != null && state.order?.id == o.id) state = state.copyWith(tripRoute: r.points);
        }
      }
      _routedFor = stage;
    } finally {
      _routing = false;
    }
  }

  void setRemaining(double m) => state = state.copyWith(remainingM: m);

  void _onOrder(Order o) {
    final me = state.profile?.id;
    if (o.driverId != me && state.order?.id == o.id) {
      // Passenger cancelled, or the order went back to search.
      state = state.copyWith(clearOrder: true, notice: 'Пассажир отменил поездку');
      return;
    }
    if (o.driverId != me) return;
    if (o.status == OrderStatus.cancelled) {
      state = state.copyWith(clearOrder: true, notice: 'Пассажир отменил поездку');
      if (!state.online) _location.stop();
      return;
    }
    state = state.copyWith(order: o, clearOffer: true);
    unawaited(buildRoute());
  }

  void _onPosition(Position p) {
    final pos = LatLng(p.latitude, p.longitude);
    final hadPosition = state.position != null;
    state = state.copyWith(position: pos, heading: p.heading >= 0 ? p.heading : state.heading);
    if (!hadPosition && state.order?.status == OrderStatus.assigned && state.approach.isEmpty) unawaited(buildRoute(force: true));
    final sent = ref.read(realtimeProvider).send({'type': 'location', 'lat': p.latitude, 'lng': p.longitude, 'heading': p.heading});
    if (!sent && DateTime.now().difference(_lastHttpLocation) > const Duration(seconds: 5)) {
      _lastHttpLocation = DateTime.now();
      unawaited(_api.sendLocation(p.latitude, p.longitude, p.heading).catchError((_) {}));
    }
  }

  void _tick() {
    if (state.online) {
      // Keeps the driver visible if the socket silently died.
      final p = state.position;
      if (p != null && !ref.read(realtimeProvider).isConnected) {
        unawaited(_api.sendLocation(p.latitude, p.longitude, state.heading).catchError((_) {}));
      }
      unawaited(loadDemand());
    }
    if (state.order?.isActive == true || (state.online && state.offer == null)) unawaited(refresh());
  }

  /// Fallback for pre-check: whether location is turned on at all.
  Future<bool> locationEnabled() => Geolocator.isLocationServiceEnabled();
}

final driverProvider = NotifierProvider<DriverController, DriverState>(DriverController.new);
