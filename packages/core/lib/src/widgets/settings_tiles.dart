import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../providers.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';

/// App-wide language choice; null follows the phone.
final localeProvider = StateProvider<Locale?>((_) => null);

/// Language, legal links, support, sign-out and account deletion — the same in both apps.
class AccountSettingsSection extends ConsumerWidget {
  const AccountSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return Column(children: [
      ListTile(
        leading: const Icon(Icons.language_rounded),
        title: Text(s.t('language')),
        trailing: Text(switch (s.lang) { 'kk' => 'Қазақша', 'en' => 'English', _ => 'Русский' }),
        onTap: () => _pickLanguage(context, ref),
      ),
      ListTile(leading: const Icon(Icons.support_agent_rounded), title: Text(s.t('support')), onTap: () => dial(NomoConfig.supportPhone)),
      ListTile(leading: const Icon(Icons.shield_outlined), title: Text(s.t('privacy')), onTap: () => openUrl(NomoConfig.privacyUrl)),
      ListTile(leading: const Icon(Icons.description_outlined), title: Text(s.t('terms')), onTap: () => openUrl(NomoConfig.termsUrl)),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.logout_rounded),
        title: Text(s.t('logout')),
        onTap: () => ref.read(authProvider.notifier).signOut(),
      ),
      ListTile(
        leading: const Icon(Icons.delete_forever_rounded, color: NomoColors.danger),
        title: Text(s.t('delete_account'), style: const TextStyle(color: NomoColors.danger)),
        onTap: () async {
          final ok = await confirm(context, title: s.t('delete_account'), text: s.t('delete_confirm'), ok: s.t('delete'), danger: true);
          if (!ok) return;
          try {
            await ref.read(apiProvider).deleteAccount();
            await ref.read(authProvider.notifier).signOut();
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
        },
      ),
    ]);
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (code, label) in const [('ru', 'Русский'), ('kk', 'Қазақша'), ('en', 'English')])
            ListTile(title: Text(label), onTap: () => Navigator.pop(c, code)),
        ]),
      ),
    );
    if (code == null) return;
    ref.read(localeProvider.notifier).state = Locale(code);
    try {
      await ref.read(apiProvider).updateMe(locale: code);
    } catch (_) {}
  }
}
