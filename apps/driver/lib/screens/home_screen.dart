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
  final _map = MapController();
  bool _ready = false;
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
      final p = next.position;
      if (_ready && _follow && p != null && p != prev?.position) _map.move(p, _map.camera.zoom);
    });

    final o = s.order;
    final pins = <MapPin>[
      if (s.position != null) MapPin(PinKind.car, s.position!.latitude, s.position!.longitude, heading: s.heading, key: 'me'),
      if (o != null && o.isActive && o.status != OrderStatus.inProgress) MapPin(PinKind.pickup, o.from.lat, o.from.lng),
      if (o != null && o.isActive) MapPin(PinKind.destination, o.to.lat, o.to.lng),
    ];
    final route = o == null || !o.isActive
        ? const <LatLng>[]
        : [if (s.position != null) s.position!, if (o.status != OrderStatus.inProgress) toLatLng(o.from), toLatLng(o.to)];

    return Scaffold(
      drawer: const _Menu(),
      body: Stack(children: [
        Positioned.fill(
          child: NomoMap(
            controller: _map,
            center: s.position ?? const LatLng(NomoConfig.defaultLat, NomoConfig.defaultLng),
            zoom: 15,
            pins: pins,
            route: route,
            heat: s.online && o == null ? [for (final d in s.demand) HeatSpot(d.lat, d.lng, d.level)] : const [],
            onReady: () => _ready = true,
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
                onTap: () {
                  setState(() => _follow = true);
                  if (_ready && s.position != null) _map.move(s.position!, 16);
                },
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
