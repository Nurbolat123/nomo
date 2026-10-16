/// Build-time settings, passed with --dart-define.
///
///   flutter run --dart-define=API_URL=https://api.nomo.kz
class NomoConfig {
  /// Backend base URL. Android emulator reaches the host machine at 10.0.2.2.
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');

  /// WebSocket URL derived from [apiUrl].
  static String get wsUrl => '${apiUrl.replaceFirst(RegExp('^http'), 'ws')}/v1/ws';

  /// Yandex MapKit key (developer.tech.yandex.ru → MapKit Mobile SDK).
  /// With a key the apps use Yandex maps and road routes; without it they
  /// fall back to OpenStreetMap tiles and straight-line routes.
  ///   flutter run --dart-define=YANDEX_MAPKIT_KEY=xxxxxxxx
  static const yandexKey = String.fromEnvironment('YANDEX_MAPKIT_KEY');
  static bool get hasYandexMaps => yandexKey.isNotEmpty;

  /// Fallback map tiles (only without a Yandex key). OSM's public server is
  /// for development only.
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
