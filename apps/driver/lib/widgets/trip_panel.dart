import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nomo_core/nomo_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/driver_controller.dart';

/// The accepted trip: to pickup → waiting → driving → summary and rating.
class TripPanel extends ConsumerWidget {
  const TripPanel({super.key, required this.order});
  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
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
          child: order.status == OrderStatus.completed ? _Summary(order: order) : _Active(order: order),
        ),
      ),
    );
  }
}

class _Active extends ConsumerWidget {
  const _Active({required this.order});
  final Order order;

  Future<void> _navigate(Place to) async {
    final lat = to.lat, lng = to.lng;
    final candidates = [
      Uri.parse('dgis://2gis.ru/routeSearch/rsType/car/to/$lng,$lat'),
      Uri.parse('yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lng'),
      if (Platform.isIOS) Uri.parse('maps://?daddr=$lat,$lng&dirflg=d'),
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
    ];
    for (final u in candidates) {
      try {
        if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    final ctl = ref.read(driverProvider.notifier);
    final o = order;
    final toPickup = o.status != OrderStatus.inProgress;
    final target = toPickup ? o.from : o.to;
    final (title, action, run) = switch (o.status) {
      OrderStatus.assigned => (t.t('to_pickup'), t.t('arrived'), ctl.arrived),
      OrderStatus.arrived => (t.t('driver_arrived'), t.t('start_trip'), ctl.startTrip),
      _ => (t.t('trip'), t.t('finish_trip'), ctl.complete),
    };
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        Text(money(o.price), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ]),
      const SizedBox(height: 8),
      Text(target.addr.isEmpty ? '—' : target.addr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      if (o.comment.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('«${o.comment}»', style: const TextStyle(color: NomoColors.ink2))),
      if (o.passenger != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Text(o.passenger!.name.isEmpty ? '—' : o.passenger!.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            RatingBadge(o.passenger!.rating),
            const Spacer(),
            Text(o.paymentMethod == 'cash' ? t.t('cash') : t.t('card'), style: const TextStyle(color: NomoColors.ink2)),
          ]),
        ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        RoundAction(icon: Icons.navigation_rounded, label: t.t('navigate'), onTap: () => _navigate(target)),
        RoundAction(
          icon: Icons.call_rounded,
          label: t.t('call'),
          onTap: () async {
            try {
              dial(await ref.read(apiProvider).callNumber(o.id));
            } catch (e) {
              if (context.mounted) showError(context, e);
            }
          },
        ),
        RoundAction(
          icon: Icons.chat_bubble_rounded,
          label: t.t('chat'),
          onTap: () => context.push(Uri(path: '/chat/${o.id}', queryParameters: {
            'title': o.passenger?.name.isNotEmpty == true ? o.passenger!.name : t.t('chat'),
            'me': o.driverId ?? '',
          }).toString()),
        ),
        if (toPickup)
          RoundAction(
            icon: Icons.close_rounded,
            label: t.t('cancel'),
            onTap: () async {
              if (!await confirm(context, title: t.t('cancel_confirm'), ok: t.t('cancel_ride'), danger: true)) return;
              try {
                await ctl.cancelTrip();
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
          ),
      ]),
      const SizedBox(height: 12),
      BusyButton(label: action, color: NomoColors.gold, textColor: NomoColors.black, onPressed: run),
    ]);
  }
}

class _Summary extends ConsumerStatefulWidget {
  const _Summary({required this.order});
  final Order order;

  @override
  ConsumerState<_Summary> createState() => _SummaryState();
}

class _SummaryState extends ConsumerState<_Summary> {
  int _stars = 5;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final o = widget.order;
    final total = o.finalPrice ?? o.price;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t.t('ride_done'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: o.paymentMethod == 'cash' ? NomoColors.gold : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
        child: Text(
          o.paymentMethod == 'cash' ? t.f('collect_cash', {'sum': money(total)}) : t.f('paid_by_card', {'sum': money(total)}),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: o.paymentMethod == 'cash' ? NomoColors.black : null),
        ),
      ),
      const SizedBox(height: 16),
      Text(t.t('rate_passenger'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
      StarPicker(value: _stars, onChanged: (v) => setState(() => _stars = v)),
      const SizedBox(height: 8),
      BusyButton(label: t.t('done'), onPressed: () => ref.read(driverProvider.notifier).ratePassenger(_stars)),
    ]);
  }
}
