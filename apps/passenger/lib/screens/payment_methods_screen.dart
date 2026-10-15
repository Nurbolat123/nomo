import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/ride_controller.dart';

/// Saved cards. Adding a card opens the acquirer's tokenization page in
/// production (see docs/payments.md); in debug builds a test card is added.
class PaymentMethodsScreen extends ConsumerStatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  ConsumerState<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(rideProvider.notifier).loadCards());
  }

  Future<void> _addCard() async {
    final t = S.of(context);
    if (!kDebugMode && !NomoConfig.apiUrl.contains('localhost') && !NomoConfig.apiUrl.contains('10.0.2.2')) {
      // TODO(payments): open the acquirer's card page (WebView) and pass its token to api.addCard.
      showInfo(context, t.t('card_dev_note'));
      return;
    }
    final ok = await confirm(context, title: t.t('add_card'), text: t.t('card_dev_note'), ok: t.t('add_card'));
    if (!ok) return;
    try {
      await ref.read(apiProvider).addCard(token: 'tok_test_${DateTime.now().millisecondsSinceEpoch}', brand: 'visa', last4: '4242');
      await ref.read(rideProvider.notifier).loadCards();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final s = ref.watch(rideProvider);
    final ctl = ref.read(rideProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(t.t('payment_methods'))),
      body: ListView(children: [
        RadioListTile<String>(
          value: 'cash',
          groupValue: s.payment == 'cash' ? 'cash' : s.card?.id,
          onChanged: (_) => ctl.payCash(),
          title: Text(t.t('cash')),
          secondary: const Icon(Icons.payments_outlined),
        ),
        for (final c in s.cards)
          RadioListTile<String>(
            value: c.id,
            groupValue: s.payment == 'cash' ? 'cash' : s.card?.id,
            onChanged: (_) => ctl.payCard(c),
            title: Text(c.label),
            secondary: IconButton(
              tooltip: t.t('delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await ref.read(apiProvider).deleteCard(c.id);
                if (s.card?.id == c.id) ctl.payCash();
                await ctl.loadCards();
              },
            ),
          ),
        ListTile(leading: const Icon(Icons.add_rounded), title: Text(t.t('add_card')), onTap: _addCard),
      ]),
    );
  }
}
