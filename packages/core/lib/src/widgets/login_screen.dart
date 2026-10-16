import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../format.dart';
import '../providers.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';
import 'nomo_logo.dart';

/// Phone + SMS code sign-in, shared by both apps.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.logoSuffix});
  final String? logoSuffix;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeStep = false;
  int _resendIn = 0;
  Timer? _timer;

  String get _fullPhone => '+7${_phone.text.replaceAll(RegExp(r'\D'), '')}';
  bool get _phoneValid => _phone.text.replaceAll(RegExp(r'\D'), '').length == 10;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final wait = await ref.read(apiProvider).requestCode(_fullPhone, ref.read(appRoleProvider));
    setState(() {
      _codeStep = true;
      _resendIn = wait;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn = (_resendIn - 1).clamp(0, 999));
      if (_resendIn == 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    await ref.read(apiProvider).verifyCode(_fullPhone, _code.text.trim(), ref.read(appRoleProvider));
    ref.read(authProvider.notifier).signedIn();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - 56),
              child: IntrinsicHeight(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NomoLogo(size: 36, suffix: widget.logoSuffix),
                  const SizedBox(height: 48),
                  Text(_codeStep ? s.t('code_title') : s.t('phone_title'), style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    _codeStep ? s.f('code_sent', {'phone': prettyPhone(_fullPhone)}) : s.t('phone_hint'),
                    style: theme.textTheme.bodyLarge?.copyWith(color: NomoColors.ink2),
                  ),
                  const SizedBox(height: 24),
                  if (!_codeStep)
                    TextField(
                      controller: _phone,
                      autofocus: true,
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumberNational],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 1),
                      decoration: const InputDecoration(prefixText: '+7  ', hintText: '701 123 45 67'),
                      onChanged: (_) => setState(() {}),
                    )
                  else ...[
                    TextField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 16),
                      decoration: const InputDecoration(hintText: '••••'),
                      onChanged: (v) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      TextButton(
                        onPressed: _resendIn > 0
                            ? null
                            : () => _requestCode().catchError((Object e) {
                                  if (context.mounted) showError(context, e);
                                }),
                        child: Text(_resendIn > 0 ? s.f('resend_in', {'s': _resendIn}) : s.t('resend')),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          _codeStep = false;
                          _code.clear();
                        }),
                        child: Text(s.t('change_number')),
                      ),
                    ]),
                  ],
                  const Spacer(),
                  const SizedBox(height: 24),
                  BusyButton(
                    label: s.t('continue'),
                    onPressed: _codeStep
                        ? (_code.text.length == 4 ? _verify : null)
                        : (_phoneValid ? _requestCode : null),
                  ),
                  const SizedBox(height: 16),
                  _Legal(s: s),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legal extends StatelessWidget {
  const _Legal({required this.s});
  final S s;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: NomoColors.ink2);
    final link = style?.copyWith(decoration: TextDecoration.underline, color: Theme.of(context).colorScheme.onSurface);
    return Text.rich(
      TextSpan(style: style, children: [
        TextSpan(text: '${s.t('agree')}. '),
        TextSpan(text: s.t('terms'), style: link, recognizer: TapGestureRecognizer()..onTap = () => openUrl(NomoConfig.termsUrl)),
        const TextSpan(text: ' · '),
        TextSpan(text: s.t('privacy'), style: link, recognizer: TapGestureRecognizer()..onTap = () => openUrl(NomoConfig.privacyUrl)),
      ]),
    );
  }
}
