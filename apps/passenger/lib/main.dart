import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomo_core/nomo_core.dart';

import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMaps();
  final tokens = TokenStore();
  await tokens.load();
  runApp(ProviderScope(
    overrides: [
      appRoleProvider.overrideWithValue('passenger'),
      tokenStoreProvider.overrideWithValue(tokens),
    ],
    child: const PassengerApp(),
  ));
}

class PassengerApp extends ConsumerStatefulWidget {
  const PassengerApp({super.key});

  @override
  ConsumerState<PassengerApp> createState() => _PassengerAppState();
}

class _PassengerAppState extends ConsumerState<PassengerApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (ref.read(authProvider) == AuthStatus.signedIn) ref.read(realtimeProvider).connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && ref.read(authProvider) == AuthStatus.signedIn) {
      ref.read(realtimeProvider).connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Nomo',
      debugShowCheckedModeBanner: false,
      theme: NomoTheme.light(),
      darkTheme: NomoTheme.dark(),
      locale: ref.watch(localeProvider),
      supportedLocales: S.supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
