import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'realtime.dart';
import 'token_store.dart';

/// Which app is running: decides the role used at sign-in.
final appRoleProvider = Provider<String>((_) => throw UnimplementedError('override appRoleProvider'));

final tokenStoreProvider = Provider<TokenStore>((_) => throw UnimplementedError('override tokenStoreProvider after load()'));

enum AuthStatus { signedOut, signedIn }

class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() => ref.read(tokenStoreProvider).hasSession ? AuthStatus.signedIn : AuthStatus.signedOut;

  void signedIn() {
    state = AuthStatus.signedIn;
    ref.read(realtimeProvider).connect();
  }

  Future<void> signOut() async {
    ref.read(realtimeProvider).disconnect();
    await ref.read(tokenStoreProvider).clear();
    state = AuthStatus.signedOut;
  }
}

final authProvider = NotifierProvider<AuthController, AuthStatus>(AuthController.new);

final apiProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.read(tokenStoreProvider),
    onSignedOut: () => ref.read(authProvider.notifier).signOut(),
  );
});

final realtimeProvider = Provider<RealtimeClient>((ref) {
  final api = ref.read(apiProvider);
  final rt = RealtimeClient(
    ref.read(tokenStoreProvider),
    // Any authorized call refreshes an expired access token.
    refreshToken: () async {
      await api.me();
    },
  );
  ref.onDispose(rt.dispose);
  return rt;
});
