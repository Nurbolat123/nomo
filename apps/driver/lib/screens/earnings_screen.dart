import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/driver_controller.dart';

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  bool _week = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(driverProvider.notifier).loadEarnings());
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final e = ref.watch(driverProvider.select((s) => s.earnings));
    final p = e == null ? null : (_week ? e.week : e.today);
    return Scaffold(
      appBar: AppBar(title: Text(t.t('earnings'))),
      body: e == null || p == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(driverProvider.notifier).loadEarnings(),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(t.t('today'))),
                    ButtonSegment(value: true, label: Text(t.t('week'))),
                  ],
                  selected: {_week},
                  onSelectionChanged: (v) => setState(() => _week = v.first),
                ),
                const SizedBox(height: 24),
                Text(money(p.earned), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1)),
                Text('${t.t('trips')}: ${p.trips}', style: const TextStyle(color: NomoColors.ink2, fontSize: 16)),
                const SizedBox(height: 24),
                _Row(t.t('cash'), money(p.cash)),
                _Row(t.t('card'), money(p.card)),
                _Row(t.t('tips'), money(p.tips)),
                _Row(t.t('commission'), money(-p.commission)),
                const Divider(height: 32),
                _Row(t.t('balance'), money(e.balance), bold: true),
              ]),
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});
  final String label, value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Text(label, style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.w800 : FontWeight.w700)),
        ]),
      );
}
