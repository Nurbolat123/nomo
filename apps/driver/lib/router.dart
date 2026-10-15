import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nomo_core/nomo_core.dart';

import 'screens/earnings_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/root_screen.dart';

class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final signedIn = ref.read(authProvider) == AuthStatus.signedIn;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn && !atLogin) return '/login';
      if (signedIn && atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen(logoSuffix: 'driver')),
      GoRoute(path: '/', builder: (_, __) => const RootScreen()),
      GoRoute(path: '/earnings', builder: (_, __) => const EarningsScreen()),
      GoRoute(path: '/history', builder: (_, __) => const DriverHistoryScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const DriverProfileScreen()),
      GoRoute(
        path: '/chat/:id',
        builder: (_, s) => ChatScreen(
          orderId: s.pathParameters['id']!,
          title: s.uri.queryParameters['title'] ?? 'Чат',
          myId: s.uri.queryParameters['me'] ?? '',
        ),
      ),
    ],
  );
});
