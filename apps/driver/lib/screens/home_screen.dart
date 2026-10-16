import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/driver_controller.dart';
import '../widgets/disclosure.dart';
import '../widgets/offer_card.dart';
import '../widgets/trip_panel.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  final _map = NomoMapController();
  bool _follow = true;

  Future<void> _toggleOnline(bool online) async {
    final ctl = ref.read(driverProvider.notifier);
    try {
      if (online) {
        if (!await LocationDisclosure.accepted(context)) return;
        await ctl.goOnline();
      } else {
        await ctl.goOffline();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(driverProvider);
    final t = S.of(context);
    ref.listen<DriverState>(driverProvider, (prev, next) {
      if (next.notice != null && next.notice != prev?.notice) {
        showInfo(context, next.notice!);
        ref.read(driverProvider.notifier).clearNotice();
      }
      // New stage of the trip: follow the car again.
      if (prev?.order?.status != next.order?.status || (prev?.offer == null) != (next.offer == null)) {
        _follow = true; // the screen rebuilds with the new state anyway
      }
    });

    final o = s.order;
    final offer = s.offer;
    final active = o != null && o.isActive;
    final pins = <MapPin>[
      if (active && o.status != OrderStatus.inProgress) MapPin(PinKind.pickup, o.from.lat, o.from.lng, key: 'pickup'),
      if (active) MapPin(PinKind.destination, o.to.lat, o.to.lng, key: 'destination'),
      if (!active && offer != null) MapPin(PinKind.pickup, offer.from.lat, offer.from.lng, key: 'offer-pickup'),
      if (!active && offer != null) MapPin(PinKind.destination, offer.to.lat, offer.to.lng, key: 'offer-destination'),
    ];
    final followWith = <LatLng>[
      if (active && o.status == OrderStatus.assigned) LatLng(o.from.lat, o.from.lng),
      if (!active && offer != null) LatLng(offer.from.lat, offer.from.lng),
    ];
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      drawer: const _Menu(),
      body: Stack(children: [
        Positioned.fill(
          child: NomoMap(
            controller: _map,
            center: s.position ?? const LatLng(NomoConfig.defaultLat, NomoConfig.defaultLng),
            zoom: 16,
            pins: pins,
            route: s.activeRoute,
            car: s.position == null ? null : CarTarget(s.position!, heading: s.heading),
            showTrail: active,
            followCar: _follow,
            followWith: followWith,
            heat: s.online && o == null && offer == null ? [for (final d in s.demand) HeatSpot(d.lat, d.lng, d.level)] : const [],
            padding: EdgeInsets.only(top: 110, bottom: size.height * (offer != null ? 0.5 : 0.36), left: 24, right: 24),
            onOffRoute: () => ref.read(driverProvider.notifier).buildRoute(force: true),
            onRemaining: ref.read(driverProvider.notifier).setRemaining,
            onMoveStart: () => setState(() => _follow = false),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Builder(builder: (c) => _Round(icon: Icons.menu_rounded, tooltip: t.t('menu'), onTap: () => Scaffold.of(c).openDrawer())),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/earnings'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: NomoColors.black, borderRadius: BorderRadius.circular(24)),
                  child: Text(
                    money(s.earnings?.today.earned ?? 0),
                    style: const TextStyle(color: NomoColors.gold, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
              const Spacer(),
              _Round(
                icon: _follow ? Icons.navigation_rounded : Icons.navigation_outlined,
                tooltip: t.t('my_location'),
                onTap: () => setState(() => _follow = true),
              ),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: o != null
              ? TripPanel(order: o)
              : s.offer != null
                  ? OfferCard(offer: s.offer!)
                  : _OnlinePanel(state: s, onToggle: _toggleOnline),
        ),
      ]),
    );
  }
}

class _OnlinePanel extends StatelessWidget {
  const _OnlinePanel({required this.state, required this.onToggle});
  final DriverState state;
  final Future<void> Function(bool) onToggle;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final online = state.online;
    final e = state.earnings?.today;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24)],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: online ? NomoColors.success : NomoColors.ink2, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(online ? t.t('online') : t.t('offline_status'), style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              if (e != null) Text('${t.t('trips')}: ${e.trips}', style: const TextStyle(color: NomoColors.ink2, fontWeight: FontWeight.w600)),
            ]),
            if (online && state.demand.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.local_fire_department_rounded, color: NomoColors.gold, size: 18),
                const SizedBox(width: 4),
                Text(t.t('demand'), style: const TextStyle(color: NomoColors.ink2)),
              ]),
            ],
            const SizedBox(height: 16),
            BusyButton(
              label: online ? t.t('go_offline') : t.t('go_online'),
              color: online ? cs.surfaceContainerHighest : NomoColors.gold,
              textColor: online ? cs.onSurface : NomoColors.black,
              onPressed: () => onToggle(!online),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 3,
        child: IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onTap, padding: const EdgeInsets.all(12)),
      );
}

class _Menu extends ConsumerWidget {
  const _Menu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    final p = ref.watch(driverProvider.select((s) => s.profile));
    void go(String path) {
      Navigator.pop(context);
      context.push(path);
    }

    return Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 8), child: NomoLogo(size: 28, suffix: 'driver')),
          if (p != null)
            ListTile(
              leading: Initials(p.name),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Row(children: [RatingBadge(p.rating), const SizedBox(width: 8), Text(p.carPlate)]),
            ),
          const Divider(),
          ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: Text(t.t('earnings')), onTap: () => go('/earnings')),
          ListTile(leading: const Icon(Icons.history_rounded), title: Text(t.t('history')), onTap: () => go('/history')),
          ListTile(leading: const Icon(Icons.person_outline_rounded), title: Text(t.t('profile')), onTap: () => go('/profile')),
          ListTile(leading: const Icon(Icons.support_agent_rounded), title: Text(t.t('support')), onTap: () => dial(NomoConfig.supportPhone)),
        ]),
      ),
    );
  }
}
