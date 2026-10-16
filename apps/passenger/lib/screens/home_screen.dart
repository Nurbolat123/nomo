import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/ride_controller.dart';
import '../widgets/idle_panel.dart';
import '../widgets/plan_panel.dart';
import '../widgets/sheet_card.dart';
import '../widgets/ride_panel.dart';
import 'address_search_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _map = NomoMapController();
  bool _dragging = false;
  bool _pickingDestination = false;
  bool _online = true;

  /// Camera keeps the car in view until the user drags the map.
  bool _follow = true;
  StreamSubscription<bool>? _conn;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(rideProvider.notifier).init());
    _conn = ref.read(realtimeProvider).connection.listen((c) {
      if (mounted) setState(() => _online = c);
    });
  }

  @override
  void dispose() {
    _conn?.cancel();
    super.dispose();
  }

  RideController get _ctl => ref.read(rideProvider.notifier);

  bool _choosingPickup(RideState s) => s.order == null && s.destination == null && !_pickingDestination;

  bool _carOnMap(RideState s) {
    final o = s.order;
    return o != null && s.driverPos != null && (o.status == OrderStatus.assigned || o.status == OrderStatus.arrived || o.status == OrderStatus.inProgress);
  }

  /// Frames the whole route (or the pickup) when nothing is being followed.
  void _frame(RideState s) {
    if (!_map.isReady) return;
    if (_carOnMap(s) && _follow) return; // the map follows the car itself
    final route = s.activeRoute;
    if (route.length >= 2) {
      _map.fit(route);
    } else if (s.pickup != null && s.destination != null) {
      _map.fit([toLatLng(s.pickup!), toLatLng(s.destination!)]);
    } else if (s.pickup != null) {
      _map.moveTo(toLatLng(s.pickup!), zoom: 16.5);
    }
  }

  Future<void> _openSearch({bool editFrom = false}) async {
    final s = ref.read(rideProvider);
    final pick = await Navigator.of(context).push<AddressPick>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AddressSearchScreen(from: s.pickup, to: s.destination, editFrom: editFrom),
    ));
    if (pick == null || !mounted) return;
    if (pick.from != null) _ctl.setPickupPlace(pick.from!);
    if (pick.pickToOnMap) {
      setState(() => _pickingDestination = true);
      return;
    }
    if (pick.to != null) {
      try {
        await _ctl.setDestination(pick.to!);
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  Future<void> _confirmMapDestination() async {
    final c = _map.center;
    if (c == null) return;
    setState(() => _pickingDestination = false);
    final addr = await ref.read(geocoderProvider).reverse(c.latitude, c.longitude);
    try {
      await _ctl.setDestination(Place(lat: c.latitude, lng: c.longitude, addr: addr));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Bubble over the pickup while the driver is on the way: "4 мин".
  String? _pickupLabel(RideState s, S t) {
    final o = s.order;
    if (o == null || o.status != OrderStatus.assigned) return null;
    final m = s.remainingM;
    if (m == null) return null;
    return minutes((m / (28000 / 3600)).round(), unit: t.t('min'));
  }

  /// Arrival time over the destination during the trip: "12:40".
  String? _destinationLabel(RideState s) {
    final o = s.order;
    if (o == null || o.status != OrderStatus.inProgress) return null;
    final m = s.remainingM ?? o.distanceM.toDouble();
    final at = DateTime.now().add(Duration(seconds: (m / (28000 / 3600)).round()));
    return '${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(rideProvider);
    final t = S.of(context);
    ref.listen<RideState>(rideProvider, (prev, next) {
      final changed = prev?.destination != next.destination ||
          prev?.order?.status != next.order?.status ||
          !identical(prev?.tripRoute, next.tripRoute) ||
          (prev?.approach.isEmpty ?? true) != next.approach.isEmpty;
      if (prev?.order?.status != next.order?.status) _follow = true;
      if (changed) WidgetsBinding.instance.addPostFrameCallback((_) => _frame(ref.read(rideProvider)));
    });

    final o = s.order;
    final showCar = _carOnMap(s);
    final size = MediaQuery.sizeOf(context);
    final pins = <MapPin>[
      if (s.myLocation != null && !_choosingPickup(s) && o == null) MapPin(PinKind.me, s.myLocation!.latitude, s.myLocation!.longitude, key: 'me'),
      if (!_choosingPickup(s) && s.pickup != null && !_pickingDestination && o?.status != OrderStatus.inProgress)
        MapPin(PinKind.pickup, s.pickup!.lat, s.pickup!.lng, key: 'pickup', label: _pickupLabel(s, t)),
      if (s.destination != null && !_pickingDestination)
        MapPin(PinKind.destination, s.destination!.lat, s.destination!.lng, key: 'destination', label: _destinationLabel(s)),
      if (o == null)
        for (var i = 0; i < s.cars.length; i++) MapPin(PinKind.car, s.cars[i].lat, s.cars[i].lng, heading: s.cars[i].heading, key: 'near$i'),
    ];
    final followWith = <LatLng>[
      if (o?.status == OrderStatus.assigned && s.pickup != null) toLatLng(s.pickup!),
      if (o?.status == OrderStatus.inProgress && s.destination != null) toLatLng(s.destination!),
    ];

    Widget panel;
    if (_pickingDestination) {
      panel = _MapPickPanel(onDone: _confirmMapDestination, onCancel: () => setState(() => _pickingDestination = false));
    } else if (o != null) {
      panel = RidePanel(state: s);
    } else if (s.planning) {
      panel = PlanPanel(state: s, onEditRoute: _openSearch);
    } else {
      panel = IdlePanel(state: s, onSearch: () => _openSearch(), onEditFrom: () => _openSearch(editFrom: true));
    }

    return Scaffold(
      drawer: const _Menu(),
      body: Stack(children: [
        Positioned.fill(
          child: NomoMap(
            controller: _map,
            center: s.pickup != null ? toLatLng(s.pickup!) : const LatLng(NomoConfig.defaultLat, NomoConfig.defaultLng),
            zoom: 16,
            pins: pins,
            route: _pickingDestination ? const [] : s.activeRoute,
            car: showCar ? CarTarget(s.driverPos!, heading: s.driverHeading) : null,
            showTrail: showCar,
            followCar: showCar && _follow,
            followWith: followWith,
            padding: EdgeInsets.only(top: 110, bottom: size.height * 0.42, left: 24, right: 24),
            onReady: () => _frame(ref.read(rideProvider)),
            onOffRoute: _ctl.rebuildApproach,
            onRemaining: _ctl.setRemaining,
            onMoveStart: () => setState(() {
              _dragging = true;
              _follow = false;
            }),
            onMoved: (c) {
              setState(() => _dragging = false);
              if (_choosingPickup(ref.read(rideProvider))) _ctl.setPickup(c);
            },
          ),
        ),
        if (_choosingPickup(s) || _pickingDestination)
          Positioned.fill(
            bottom: size.height * 0.30,
            child: Center(child: CenterPin(lifted: _dragging)),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Builder(
                builder: (c) => _MapButton(icon: Icons.menu_rounded, tooltip: t.t('menu'), onTap: () => Scaffold.of(c).openDrawer()),
              ),
              const Spacer(),
              if (!_online)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: NomoColors.danger, borderRadius: BorderRadius.circular(20)),
                  child: Text(t.t('offline'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              const Spacer(),
              _MapButton(
                icon: showCar ? (_follow ? Icons.navigation_rounded : Icons.navigation_outlined) : Icons.near_me_rounded,
                tooltip: t.t('my_location'),
                onTap: () async {
                  if (showCar) {
                    setState(() => _follow = true);
                    return;
                  }
                  await _ctl.locate();
                  final me = ref.read(rideProvider).myLocation;
                  if (me != null) _map.moveTo(me, zoom: 16.5);
                },
              ),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, a) => SlideTransition(
              position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: KeyedSubtree(key: ValueKey(panel.runtimeType), child: panel),
          ),
        ),
      ]),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black26,
      child: IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onTap, iconSize: 24, padding: const EdgeInsets.all(12)),
    );
  }
}

class _MapPickPanel extends StatelessWidget {
  const _MapPickPanel({required this.onDone, required this.onCancel});
  final VoidCallback onDone;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return SheetCard(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.t('pick_destination'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        FilledButton(onPressed: onDone, child: Text(t.t('done'))),
        TextButton(onPressed: onCancel, child: Text(t.t('cancel'))),
      ]),
    );
  }
}

class _Menu extends ConsumerWidget {
  const _Menu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 24), child: NomoLogo(size: 32)),
          ListTile(leading: const Icon(Icons.person_outline_rounded), title: Text(t.t('profile')), onTap: () => _go(context, '/profile')),
          ListTile(leading: const Icon(Icons.history_rounded), title: Text(t.t('history')), onTap: () => _go(context, '/history')),
          ListTile(leading: const Icon(Icons.credit_card_rounded), title: Text(t.t('payment_methods')), onTap: () => _go(context, '/payment')),
          ListTile(leading: const Icon(Icons.support_agent_rounded), title: Text(t.t('support')), onTap: () => dial(NomoConfig.supportPhone)),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(t.t('tagline'), style: const TextStyle(color: NomoColors.ink2, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  void _go(BuildContext context, String path) {
    Navigator.pop(context);
    context.push(path);
  }
}
