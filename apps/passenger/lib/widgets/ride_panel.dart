import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nomo_core/nomo_core.dart';
import 'package:share_plus/share_plus.dart';

import '../state/ride_controller.dart';
import 'sheet_card.dart';

/// The active trip: searching, driver on the way, arrived, in progress, done.
class RidePanel extends ConsumerWidget {
  const RidePanel({super.key, required this.state});
  final RideState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = state.order!;
    return SheetCard(
      child: switch (o.status) {
        OrderStatus.searching => _Searching(order: o),
        OrderStatus.assigned || OrderStatus.arrived || OrderStatus.inProgress => _OnTrip(state: state),
        OrderStatus.completed => _Finished(order: o),
        OrderStatus.cancelled || OrderStatus.noDrivers => _Ended(order: o),
      },
    );
  }
}

class _Searching extends ConsumerStatefulWidget {
  const _Searching({required this.order});
  final Order order;

  @override
  ConsumerState<_Searching> createState() => _SearchingState();
}

class _SearchingState extends ConsumerState<_Searching> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 96,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => CustomPaint(
            painter: _PulsePainter(_pulse.value, Theme.of(context).colorScheme.onSurface),
            child: const Center(child: NomoMark(size: 44)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(t.t('searching'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(t.t('searching_hint'), textAlign: TextAlign.center, style: const TextStyle(color: NomoColors.ink2)),
      const SizedBox(height: 8),
      Text('${widget.order.to.addr} · ${money(widget.order.price)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 16),
      OutlinedButton(onPressed: () => _cancel(context, ref, widget.order), child: Text(t.t('cancel'))),
    ]);
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.v, this.color);
  final double v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 2; i++) {
      final p = (v + i * 0.5) % 1;
      canvas.drawCircle(c, 24 + p * 30, Paint()..color = color.withValues(alpha: (1 - p) * 0.15));
    }
  }

  @override
  bool shouldRepaint(_PulsePainter o) => o.v != v;
}

Future<void> _cancel(BuildContext context, WidgetRef ref, Order o) async {
  final t = S.of(context);
  final late = o.status == OrderStatus.arrived ||
      (o.status == OrderStatus.assigned && o.assignedAt != null && DateTime.now().difference(o.assignedAt!) > const Duration(minutes: 2));
  final ok = await confirm(context,
      title: t.t('cancel_confirm'), text: late ? t.t('cancel_fee_maybe') : null, ok: t.t('cancel_ride'), cancel: t.t('keep_ride'), danger: true);
  if (!ok) return;
  try {
    await ref.read(rideProvider.notifier).cancel();
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _OnTrip extends ConsumerWidget {
  const _OnTrip({required this.state});
  final RideState state;

  String _title(S t, Order o) {
    switch (o.status) {
      case OrderStatus.assigned:
        final pos = state.driverPos;
        if (pos == null) return t.t('driver_on_way');
        final m = _meters(pos, toLatLng(o.from)) * 1.35;
        final secs = (m / (28000 / 3600)).round();
        return t.f('driver_arrives_in', {'m': minutes(secs, unit: t.t('min'))});
      case OrderStatus.arrived:
        return t.t('driver_arrived');
      default:
        final eta = (o.startedAt ?? DateTime.now()).add(Duration(seconds: o.durationS));
        return t.f('arrive_at', {'t': '${two(eta.hour)}:${two(eta.minute)}'});
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    final o = state.order!;
    final d = o.driver;
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(_title(t, o), style: Theme.of(context).textTheme.titleLarge),
      if (o.status == OrderStatus.arrived)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(t.f('driver_arrived_hint', {'m': 3}), style: const TextStyle(color: NomoColors.ink2))),
      if (o.status == OrderStatus.inProgress)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(t.t('in_ride'), style: const TextStyle(color: NomoColors.ink2))),
      const SizedBox(height: 16),
      if (d != null)
        Row(children: [
          Initials(d.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                RatingBadge(d.rating),
              ]),
              Text(d.car, style: const TextStyle(color: NomoColors.ink2)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(border: Border.all(color: cs.onSurface, width: 2), borderRadius: BorderRadius.circular(8)),
            child: Text(d.carPlate, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
        ]),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
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
          onTap: () => context.push(Uri(path: '/chat/${o.id}', queryParameters: {'title': d?.name ?? t.t('chat'), 'me': o.passengerId}).toString()),
        ),
        RoundAction(
          icon: Icons.ios_share_rounded,
          label: t.t('share'),
          onTap: () => Share.share(t.f('share_text', {
            'car': d?.car ?? '',
            'plate': d?.carPlate ?? '',
            'from': o.from.addr,
            'to': o.to.addr,
          })),
        ),
        RoundAction(
          icon: Icons.sos_rounded,
          label: t.t('sos'),
          danger: true,
          onTap: () async {
            if (await confirm(context, title: t.t('sos_title'), text: t.t('sos_text'), ok: t.t('call'), danger: true)) {
              dial(NomoConfig.emergencyPhone);
            }
          },
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Icon(o.paymentMethod == 'cash' ? Icons.payments_outlined : Icons.credit_card_rounded, size: 20),
        const SizedBox(width: 8),
        Text(o.paymentMethod == 'cash' ? t.t('cash') : t.t('card')),
        const Spacer(),
        Text(money(o.price), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ]),
      if (o.status != OrderStatus.inProgress) ...[
        const SizedBox(height: 8),
        TextButton(onPressed: () => _cancel(context, ref, o), child: Text(t.t('cancel_ride'), style: const TextStyle(color: NomoColors.danger))),
      ],
    ]);
  }
}

double _meters(LatLng a, LatLng b) {
  const r = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(a.latitude * math.pi / 180) * math.cos(b.latitude * math.pi / 180) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

class _Finished extends ConsumerStatefulWidget {
  const _Finished({required this.order});
  final Order order;

  @override
  ConsumerState<_Finished> createState() => _FinishedState();
}

class _FinishedState extends ConsumerState<_Finished> {
  int _stars = 5;
  int _tip = 0;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final api = ref.read(apiProvider);
    final o = widget.order;
    if (o.driverRating == null) await api.rateDriver(o.id, _stars, comment: _comment.text.trim());
    if (_tip > 0) await api.tip(o.id, _tip);
    ref.read(rideProvider.notifier).dismissOrder(keepRoute: false);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final o = widget.order;
    final canTip = o.paymentMethod == 'card' && o.tip == 0;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t.t('ride_done'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Row(children: [
        Text(t.t('total'), style: const TextStyle(color: NomoColors.ink2)),
        const Spacer(),
        Text(money(o.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
      ]),
      Text(o.paymentMethod == 'cash' ? t.t('cash') : t.t('card'), style: const TextStyle(color: NomoColors.ink2)),
      const SizedBox(height: 16),
      Text(t.t('rate_title'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
      StarPicker(value: _stars, onChanged: (v) => setState(() => _stars = v)),
      if (_stars < 5)
        TextField(controller: _comment, maxLength: 300, decoration: InputDecoration(hintText: t.t('comment_driver'))),
      if (canTip) ...[
        const SizedBox(height: 8),
        Text(t.t('tip'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final v in const [0, 200, 500, 1000])
            ChoiceChip(
              label: Text(v == 0 ? t.t('no_tip') : money(v)),
              selected: _tip == v,
              onSelected: (_) => setState(() => _tip = v),
            ),
        ]),
      ],
      const SizedBox(height: 16),
      BusyButton(label: t.t('rate_send'), onPressed: _submit),
    ]);
  }
}

class _Ended extends ConsumerWidget {
  const _Ended({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    final noDrivers = order.status == OrderStatus.noDrivers;
    final ctl = ref.read(rideProvider.notifier);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(noDrivers ? t.t('no_drivers') : t.t('cancelled'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      if (noDrivers) Text(t.t('no_drivers_hint'), style: const TextStyle(color: NomoColors.ink2)),
      if (order.cancelFee > 0) Text(t.f('cancel_fee_warn', {'fee': money(order.cancelFee)}), style: const TextStyle(color: NomoColors.ink2)),
      const SizedBox(height: 16),
      FilledButton(onPressed: () => ctl.dismissOrder(), child: Text(t.t('try_again'))),
      TextButton(onPressed: () => ctl.dismissOrder(keepRoute: false), child: Text(t.t('close'))),
    ]);
  }
}
