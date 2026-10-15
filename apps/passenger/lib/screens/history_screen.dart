import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomo_core/nomo_core.dart';

final _historyProvider = FutureProvider.autoDispose<List<Order>>((ref) => ref.read(apiProvider).history());

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    final data = ref.watch(_historyProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.t('history'))),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$e'),
            TextButton(onPressed: () => ref.invalidate(_historyProvider), child: Text(t.t('retry'))),
          ]),
        ),
        data: (list) => list.isEmpty
            ? Center(child: Text(t.t('history_empty'), style: const TextStyle(color: NomoColors.ink2)))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(_historyProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _TripCard(order: list[i]),
                ),
              ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final o = order;
    final status = switch (o.status) {
      OrderStatus.completed => null,
      OrderStatus.cancelled => t.t('cancelled'),
      OrderStatus.noDrivers => t.t('no_drivers'),
      _ => t.t('in_ride'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(dateTime(o.createdAt), style: const TextStyle(color: NomoColors.ink2)),
            const Spacer(),
            Text(money(o.status == OrderStatus.completed ? o.total : o.cancelFee), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          Text(o.from.addr.isEmpty ? '—' : o.from.addr, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(o.to.addr.isEmpty ? '—' : o.to.addr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (o.driver != null) Text('${o.driver!.name} · ${o.driver!.car} · ${o.driver!.carPlate}', style: const TextStyle(color: NomoColors.ink2, fontSize: 13)),
          if (status != null) Text(status, style: const TextStyle(color: NomoColors.danger, fontSize: 13)),
        ]),
      ),
    );
  }
}
