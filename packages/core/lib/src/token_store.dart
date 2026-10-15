import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps auth tokens in the Keychain (iOS) / EncryptedSharedPreferences (Android).
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _storage;
  String? _access;
  String? _refresh;

  String? get access => _access;
  String? get refresh => _refresh;
  bool get hasSession => _refresh != null;

  Future<void> load() async {
    _access = await _storage.read(key: 'access_token');
    _refresh = await _storage.read(key: 'refresh_token');
  }

  Future<void> save(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}
