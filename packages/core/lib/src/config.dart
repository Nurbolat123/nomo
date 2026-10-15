/// Build-time settings, passed with --dart-define.
///
///   flutter run --dart-define=API_URL=https://api.nomo.kz
class NomoConfig {
  /// Backend base URL. Android emulator reaches the host machine at 10.0.2.2.
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');

  /// WebSocket URL derived from [apiUrl].
  static String get wsUrl => '${apiUrl.replaceFirst(RegExp('^http'), 'ws')}/v1/ws';

  /// Map tiles. OpenStreetMap is fine for development; switch to 2GIS,
  /// Yandex or MapTiler (with your key) before launch — OSM's public tile
  /// server does not allow heavy production traffic.
  static const tileUrl = String.fromEnvironment('TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

  static const privacyUrl = String.fromEnvironment('PRIVACY_URL', defaultValue: 'https://nomo.kz/privacy');
  static const termsUrl = String.fromEnvironment('TERMS_URL', defaultValue: 'https://nomo.kz/terms');
  static const supportPhone = String.fromEnvironment('SUPPORT_PHONE', defaultValue: '+77000000099');

  /// Emergency number in Kazakhstan.
  static const emergencyPhone = '112';

  /// Start position when location is unknown: Uralsk (Oral).
  static const defaultLat = 51.2333;
  static const defaultLng = 51.3667;
}
