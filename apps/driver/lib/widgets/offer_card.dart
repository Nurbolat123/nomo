import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/driver_controller.dart';

/// Incoming order with a countdown ring: accept or skip.
class OfferCard extends ConsumerStatefulWidget {
  const OfferCard({super.key, required this.offer});
  final Offer offer;

  @override
  ConsumerState<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<OfferCard> {
  Timer? _timer;
  late Duration _total;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(OfferCard old) {
    super.didUpdateWidget(old);
    if (old.offer.orderId != widget.offer.orderId) _start();
  }

  void _start() {
    _timer?.cancel();
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    _left = widget.offer.expiresAt.difference(DateTime.now());
    _total = _left.inSeconds > 0 ? _left : const Duration(seconds: 15);
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final left = widget.offer.expiresAt.difference(DateTime.now());
      if (left <= Duration.zero) {
        _timer?.cancel();
        ref.read(driverProvider.notifier).offerExpired(widget.offer.orderId);
        return;
      }
      setState(() => _left = left);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final o = widget.offer;
    final cs = Theme.of(context).colorScheme;
    final progress = _total.inMilliseconds == 0 ? 0.0 : (_left.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 32)],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(t.t('new_order'), style: Theme.of(context).textTheme.titleLarge)),
              SizedBox.square(
                dimension: 44,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(value: progress, strokeWidth: 4, color: NomoColors.gold, backgroundColor: cs.surfaceContainerHighest),
                  Text('${(_left.inMilliseconds / 1000).ceil()}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Text(money(o.price), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            Text(
              '${o.paymentMethod == 'cash' ? t.t('cash') : t.t('card')} · ${distance(o.distanceM)} · ${minutes(o.durationS, unit: t.t('min'))}',
              style: const TextStyle(color: NomoColors.ink2, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            _Point(square: false, title: o.from.addr.isEmpty ? '—' : o.from.addr, sub: '${t.t('to_pickup')}: ${minutes(o.pickupEtaS, unit: t.t('min'))} · ${distance(o.pickupDistanceM)}'),
            const SizedBox(height: 8),
            _Point(square: true, title: o.to.addr.isEmpty ? '—' : o.to.addr),
            if (o.comment.isNotEmpty || o.childSeat || o.withPet) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (o.childSeat) Chip(label: Text(t.t('child_seat'))),
                if (o.withPet) Chip(label: Text(t.t('with_pet'))),
                if (o.comment.isNotEmpty) Chip(label: Text(o.comment)),
              ]),
            ],
            const SizedBox(height: 6),
            Row(children: [RatingBadge(o.passengerRating)]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ref.read(driverProvider.notifier).decline().catchError((Object e) {
                    if (context.mounted) showError(context, e);
                  }),
                  child: Text(t.t('decline')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: BusyButton(
                  label: t.t('accept'),
                  color: NomoColors.gold,
                  textColor: NomoColors.black,
                  onPressed: () => ref.read(driverProvider.notifier).accept(),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.square, required this.title, this.sub});
  final bool square;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface, shape: square ? BoxShape.rectangle : BoxShape.circle),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (sub != null) Text(sub!, style: const TextStyle(color: NomoColors.ink2)),
          ]),
        ),
      ]);
}
