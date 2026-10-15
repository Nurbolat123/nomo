import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/ride_controller.dart';
import 'sheet_card.dart';

/// Route chosen: tariffs with prices, payment, options and the order button.
class PlanPanel extends ConsumerWidget {
  const PlanPanel({super.key, required this.state, required this.onEditRoute});
  final RideState state;
  final VoidCallback onEditRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    final ctl = ref.read(rideProvider.notifier);
    final q = state.selectedQuote;
    final cs = Theme.of(context).colorScheme;
    return SheetCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: onEditRoute,
          borderRadius: BorderRadius.circular(12),
          child: Row(children: [
            IconButton(
              tooltip: t.t('cancel'),
              onPressed: ctl.clearDestination,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(state.pickup?.addr ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: NomoColors.ink2)),
                Text(state.destination?.addr ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
            if (q != null) Text('${distance(q.distanceM)} · ${minutes(q.durationS, unit: t.t('min'))}', style: const TextStyle(color: NomoColors.ink2)),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: state.quotes.isEmpty
              ? Center(child: state.quoting ? const CircularProgressIndicator() : TextButton(onPressed: ctl.refreshQuotes, child: Text(t.t('retry'))))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.quotes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _TariffCard(q: state.quotes[i], selected: state.quotes[i].tariff == q?.tariff, onTap: () => ctl.selectTariff(state.quotes[i].tariff)),
                ),
        ),
        if (q != null && q.surge > 1) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.bolt_rounded, color: NomoColors.gold, size: 18),
            const SizedBox(width: 4),
            Text(t.f('surge', {'k': q.surge.toStringAsFixed(1)}), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextButton.icon(
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: () => _pickPayment(context, ref),
              icon: Icon(state.payment == 'cash' ? Icons.payments_outlined : Icons.credit_card_rounded),
              label: Text(state.payment == 'cash' ? t.t('cash') : state.card!.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          TextButton.icon(
            onPressed: () => _options(context, ref),
            icon: Icon(Icons.tune_rounded, color: (state.comment.isNotEmpty || state.childSeat || state.withPet) ? NomoColors.gold : cs.onSurface),
            label: Text(t.t('options')),
          ),
        ]),
        const SizedBox(height: 8),
        BusyButton(
          label: q == null ? t.t('order') : '${t.f('order_tariff', {'tariff': q.name})} · ${money(q.price)}',
          onPressed: q == null ? null : ctl.placeOrder,
        ),
      ]),
    );
  }

  Future<void> _pickPayment(BuildContext context, WidgetRef ref) async {
    final t = S.of(context);
    final ctl = ref.read(rideProvider.notifier);
    await ctl.loadCards();
    if (!context.mounted) return;
    final cards = ref.read(rideProvider).cards;
    await showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(t.t('cash')),
            onTap: () {
              ctl.payCash();
              Navigator.pop(c);
            },
          ),
          for (final card in cards)
            ListTile(
              leading: const Icon(Icons.credit_card_rounded),
              title: Text(card.label),
              onTap: () {
                ctl.payCard(card);
                Navigator.pop(c);
              },
            ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: Text(t.t('add_card')),
            onTap: () {
              Navigator.pop(c);
              context.push('/payment');
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _options(BuildContext context, WidgetRef ref) async {
    final t = S.of(context);
    final ctl = ref.read(rideProvider.notifier);
    final comment = TextEditingController(text: state.comment);
    var child = state.childSeat, pet = state.withPet;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(c).bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.t('options'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: comment, maxLength: 300, decoration: InputDecoration(hintText: t.t('comment_driver'))),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t.t('child_seat')), value: child, onChanged: (v) => set(() => child = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t.t('with_pet')), value: pet, onChanged: (v) => set(() => pet = v)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                ctl.setOptions(comment: comment.text.trim(), childSeat: child, withPet: pet);
                Navigator.pop(c);
              },
              child: Text(t.t('done')),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TariffCard extends StatelessWidget {
  const _TariffCard({required this.q, required this.selected, required this.onTap});
  final QuoteItem q;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = S.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 116,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? cs.surface : cs.surfaceContainerHighest,
            border: Border.all(color: selected ? cs.onSurface : Colors.transparent, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(q.tariff == 'business' ? Icons.local_taxi_rounded : Icons.directions_car_filled_rounded, color: cs.onSurface),
            const Spacer(),
            Text(q.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(money(q.price), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(q.etaS == null ? '—' : minutes(q.etaS!, unit: t.t('min')), style: const TextStyle(fontSize: 12, color: NomoColors.ink2)),
          ]),
        ),
      ),
    );
  }
}
