import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nomo_core/nomo_core.dart';

final geocoderProvider = Provider<Geocoder>((_) => NominatimGeocoder());

class RideState {
  const RideState({
    this.pickup,
    this.destination,
    this.myLocation,
    this.locationDenied = false,
    this.quotes = const [],
    this.quoting = false,
    this.tariff = 'economy',
    this.payment = 'cash',
    this.card,
    this.cards = const [],
    this.comment = '',
    this.childSeat = false,
    this.withPet = false,
    this.order,
    this.driverPos,
    this.driverHeading = 0,
    this.cars = const [],
    this.places = const [],
  });

  final Place? pickup;
  final Place? destination;
  final LatLng? myLocation;
  final bool locationDenied;
  final List<QuoteItem> quotes;
  final bool quoting;
  final String tariff;
  final String payment; // cash | card
  final PaymentCard? card;
  final List<PaymentCard> cards;
  final String comment;
  final bool childSeat;
  final bool withPet;
  final Order? order;
  final LatLng? driverPos;
  final double driverHeading;
  final List<NearbyCar> cars;
  final List<SavedPlace> places;

  QuoteItem? get selectedQuote {
    for (final q in quotes) {
      if (q.tariff == tariff) return q;
    }
    return quotes.isEmpty ? null : quotes.first;
  }

  bool get planning => order == null && pickup != null && destination != null;

  RideState copyWith({
    Place? pickup,
    Place? destination,
    bool clearDestination = false,
    LatLng? myLocation,
    bool? locationDenied,
    List<QuoteItem>? quotes,
    bool? quoting,
    String? tariff,
    String? payment,
    PaymentCard? card,
    bool clearCard = false,
    List<PaymentCard>? cards,
    String? comment,
    bool? childSeat,
    bool? withPet,
    Order? order,
    bool clearOrder = false,
    LatLng? driverPos,
    bool clearDriver = false,
    double? driverHeading,
    List<NearbyCar>? cars,
    List<SavedPlace>? places,
  }) =>
      RideState(
        pickup: pickup ?? this.pickup,
        destination: clearDestination ? null : destination ?? this.destination,
        myLocation: myLocation ?? this.myLocation,
        locationDenied: locationDenied ?? this.locationDenied,
        quotes: clearDestination ? const [] : quotes ?? this.quotes,
        quoting: quoting ?? this.quoting,
        tariff: tariff ?? this.tariff,
        payment: payment ?? this.payment,
        card: clearCard ? null : card ?? this.card,
        cards: cards ?? this.cards,
        comment: comment ?? this.comment,
        childSeat: childSeat ?? this.childSeat,
        withPet: withPet ?? this.withPet,
        order: clearOrder ? null : order ?? this.order,
        driverPos: clearDriver ? null : driverPos ?? this.driverPos,
        driverHeading: driverHeading ?? this.driverHeading,
        cars: cars ?? this.cars,
        places: places ?? this.places,
      );
}

/// Everything about the current trip: points, prices, order and live driver position.
class RideController extends Notifier<RideState> {
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _poll;
  int _geocodeSeq = 0;

  ApiClient get _api => ref.read(apiProvider);

  @override
  RideState build() {
    final rt = ref.read(realtimeProvider);
    _subs.add(rt.on('order.updated').listen((e) => _onOrder(Order.fromJson(e.data as Map<String, dynamic>))));
    _subs.add(rt.on('driver.location').listen((e) {
      final d = e.data as Map<String, dynamic>;
      if (d['order_id'] != state.order?.id) return;
      state = state.copyWith(
        driverPos: LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
        driverHeading: (d['heading'] as num?)?.toDouble() ?? 0,
      );
    }));
    // Catch up on anything missed while the socket was down.
    _subs.add(rt.connection.where((c) => c).listen((_) => refreshOrder()));
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _tick());
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _poll?.cancel();
    });
    return const RideState();
  }

  Future<void> init() async {
    unawaited(refreshOrder());
    unawaited(loadCards());
    unawaited(loadPlaces());
    await locate();
  }

  Future<void> locate() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      state = state.copyWith(locationDenied: true);
      if (state.pickup == null) await setPickup(const LatLng(NomoConfig.defaultLat, NomoConfig.defaultLng));
      return;
    }
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      final me = LatLng(p.latitude, p.longitude);
      state = state.copyWith(myLocation: me, locationDenied: false);
      if (state.order == null) await setPickup(me);
    } catch (_) {
      if (state.pickup == null) await setPickup(const LatLng(NomoConfig.defaultLat, NomoConfig.defaultLng));
    }
  }

  /// Sets the pickup to a map point and looks up its address.
  Future<void> setPickup(LatLng p) async {
    final seq = ++_geocodeSeq;
    state = state.copyWith(pickup: Place(lat: p.latitude, lng: p.longitude, addr: state.pickup?.addr ?? ''));
    unawaited(_loadCars());
    final addr = await ref.read(geocoderProvider).reverse(p.latitude, p.longitude);
    if (seq != _geocodeSeq) return;
    state = state.copyWith(pickup: Place(lat: p.latitude, lng: p.longitude, addr: addr));
    if (state.destination != null) unawaited(refreshQuotes());
  }

  void setPickupPlace(Place p) {
    _geocodeSeq++;
    state = state.copyWith(pickup: p);
    if (state.destination != null) unawaited(refreshQuotes());
  }

  Future<void> setDestination(Place p) async {
    state = state.copyWith(destination: p);
    await refreshQuotes();
  }

  void clearDestination() => state = state.copyWith(clearDestination: true);

  Future<void> refreshQuotes() async {
    final from = state.pickup, to = state.destination;
    if (from == null || to == null) return;
    state = state.copyWith(quoting: true);
    try {
      final q = await _api.quote(from, to);
      state = state.copyWith(quotes: q, quoting: false);
    } catch (_) {
      state = state.copyWith(quoting: false);
      rethrow;
    }
  }

  void selectTariff(String t) => state = state.copyWith(tariff: t);
  void payCash() => state = state.copyWith(payment: 'cash', clearCard: true);
  void payCard(PaymentCard c) => state = state.copyWith(payment: 'card', card: c);
  void setOptions({String? comment, bool? childSeat, bool? withPet}) =>
      state = state.copyWith(comment: comment, childSeat: childSeat, withPet: withPet);

  Future<void> loadCards() async {
    try {
      state = state.copyWith(cards: await _api.cards());
    } catch (_) {}
  }

  Future<void> loadPlaces() async {
    try {
      state = state.copyWith(places: await _api.places());
    } catch (_) {}
  }

  Future<void> placeOrder() async {
    final from = state.pickup!, to = state.destination!;
    final o = await _api.createOrder(
      from: from,
      to: to,
      tariff: state.selectedQuote?.tariff ?? state.tariff,
      paymentMethod: state.payment,
      paymentMethodId: state.card?.id,
      comment: state.comment,
      childSeat: state.childSeat,
      withPet: state.withPet,
    );
    state = state.copyWith(order: o, clearDriver: true);
  }

  Future<void> cancel() async {
    final o = state.order;
    if (o == null) return;
    _onOrder(await _api.cancelOrder(o.id));
  }

  /// Leaves the finished/cancelled trip screen; keeps the route for a quick re-order.
  void dismissOrder({bool keepRoute = true}) {
    state = state.copyWith(clearOrder: true, clearDriver: true, clearDestination: !keepRoute);
    if (keepRoute) unawaited(refreshQuotes().catchError((_) {}));
  }

  Future<void> refreshOrder() async {
    try {
      final current = state.order;
      if (current != null && !current.isActive) return;
      final o = current != null ? await _api.order(current.id) : await _api.activeOrder();
      if (o != null) _onOrder(o);
    } catch (_) {}
  }

  void _onOrder(Order o) {
    final cur = state.order;
    if (cur != null && cur.id != o.id && cur.isActive) return;
    if (cur == null && !o.isActive) return;
    state = state.copyWith(
      order: o,
      pickup: o.from,
      destination: o.to,
      clearDriver: o.driverId == null,
    );
  }

  Future<void> _loadCars() async {
    final p = state.pickup;
    if (p == null || state.order != null) return;
    try {
      state = state.copyWith(cars: await _api.nearby(p.lat, p.lng));
    } catch (_) {}
  }

  void _tick() {
    if (state.order?.isActive == true) {
      refreshOrder();
    } else {
      _loadCars();
    }
  }
}

final rideProvider = NotifierProvider<RideController, RideState>(RideController.new);
