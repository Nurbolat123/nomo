import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomo_core/nomo_core.dart';

final _historyProvider = FutureProvider.autoDispose<List<Order>>((ref) => ref.read(apiProvider).driverHistory());

class DriverHistoryScreen extends ConsumerWidget {
  const DriverHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.t('history'))),
      body: ref.watch(_historyProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: TextButton(onPressed: () => ref.invalidate(_historyProvider), child: Text('$e\n${t.t('retry')}'))),
            data: (list) => list.isEmpty
                ? Center(child: Text(t.t('history_empty'), style: const TextStyle(color: NomoColors.ink2)))
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(_historyProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final o = list[i];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Text(o.to.addr.isEmpty ? '—' : o.to.addr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${dateTime(o.createdAt)} · ${o.paymentMethod == 'cash' ? t.t('cash') : t.t('card')}'
                                '${o.status == OrderStatus.completed ? '' : ' · ${t.t('cancelled')}'}'),
                            trailing: Text(money(o.status == OrderStatus.completed ? o.total : o.cancelFee), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ),
                        );
                      },
                    ),
                  ),
          ),
    );
  }
}
