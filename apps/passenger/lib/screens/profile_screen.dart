import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nomo_core/nomo_core.dart';

import '../state/ride_controller.dart';

final _meProvider = FutureProvider.autoDispose<Me>((ref) => ref.read(apiProvider).me());

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = S.of(context);
    final me = ref.watch(_meProvider);
    final places = ref.watch(rideProvider.select((s) => s.places));
    return Scaffold(
      appBar: AppBar(title: Text(t.t('profile'))),
      body: ListView(children: [
        me.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ListTile(title: Text('$e')),
          data: (m) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Initials(m.name, size: 52),
            title: Text(m.name.isEmpty ? t.t('name') : m.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            subtitle: Text(prettyPhone(m.phone)),
            trailing: const Icon(Icons.edit_rounded),
            onTap: () => _editName(context, ref, m.name),
          ),
        ),
        const Divider(),
        ListTile(leading: const Icon(Icons.credit_card_rounded), title: Text(t.t('payment_methods')), onTap: () => context.push('/payment')),
        ListTile(leading: const Icon(Icons.history_rounded), title: Text(t.t('history')), onTap: () => context.push('/history')),
        if (places.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(t.t('saved_places'), style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final p in places)
            ListTile(
              leading: const Icon(Icons.bookmark_rounded),
              title: Text(p.label),
              subtitle: Text(p.place.addr, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: t.t('delete'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  await ref.read(apiProvider).deletePlace(p.id);
                  await ref.read(rideProvider.notifier).loadPlaces();
                },
              ),
            ),
        ],
        const Divider(),
        const AccountSettingsSection(),
        const SizedBox(height: 24),
      ]),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final t = S.of(context);
    final ctl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.t('name')),
        content: TextField(controller: ctl, autofocus: true, textCapitalization: TextCapitalization.words, maxLength: 60),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t.t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(t.t('save'))),
        ],
      ),
    );
    if (name == null) return;
    try {
      await ref.read(apiProvider).updateMe(name: name);
      ref.invalidate(_meProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
