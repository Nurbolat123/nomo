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
      appRoleProvider.overrideWithValue('driver'),
      tokenStoreProvider.overrideWithValue(tokens),
    ],
    child: const DriverApp(),
  ));
}

class DriverApp extends ConsumerStatefulWidget {
  const DriverApp({super.key});

  @override
  ConsumerState<DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends ConsumerState<DriverApp> with WidgetsBindingObserver {
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
      title: 'Nomo Driver',
      debugShowCheckedModeBanner: false,
      theme: NomoTheme.light(),
      darkTheme: NomoTheme.dark(),
      // Drivers work at night: dark theme by default.
      themeMode: ThemeMode.dark,
      locale: ref.watch(localeProvider),
      supportedLocales: S.supported,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
