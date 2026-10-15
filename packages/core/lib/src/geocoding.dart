import 'package:dio/dio.dart';

import 'models.dart';

/// Address search and reverse geocoding.
///
/// [NominatimGeocoder] uses OpenStreetMap's free service, which allows at
/// most ~1 request per second: fine for development. Before launch implement
/// this interface with 2GIS Catalog API or Yandex Geocoder using your key.
abstract class Geocoder {
  Future<List<Place>> search(String query, {double? nearLat, double? nearLng});
  Future<String> reverse(double lat, double lng);
}

class NominatimGeocoder implements Geocoder {
  NominatimGeocoder({this.countryCodes = 'kz'})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://nominatim.openstreetmap.org',
          headers: {'User-Agent': 'NomoTaxi/1.0 (support@nomo.kz)'},
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ));

  final Dio _dio;
  final String countryCodes;

  @override
  Future<List<Place>> search(String query, {double? nearLat, double? nearLng}) async {
    if (query.trim().length < 3) return [];
    try {
      final r = await _dio.get('/search', queryParameters: {
        'q': query,
        'format': 'jsonv2',
        'addressdetails': 1,
        'limit': 8,
        'countrycodes': countryCodes,
        'accept-language': 'ru',
        if (nearLat != null && nearLng != null) 'viewbox': '${nearLng - 0.3},${nearLat + 0.2},${nearLng + 0.3},${nearLat - 0.2}',
      });
      return (r.data as List).map((e) {
        final m = e as Map<String, dynamic>;
        return Place(
          lat: double.parse(m['lat'] as String),
          lng: double.parse(m['lon'] as String),
          addr: _short(m),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> reverse(double lat, double lng) async {
    try {
      final r = await _dio.get('/reverse', queryParameters: {
        'lat': lat,
        'lon': lng,
        'format': 'jsonv2',
        'addressdetails': 1,
        'zoom': 18,
        'accept-language': 'ru',
      });
      return _short(r.data as Map<String, dynamic>);
    } catch (_) {
      return '';
    }
  }

  String _short(Map<String, dynamic> m) {
    final a = (m['address'] as Map?)?.cast<String, dynamic>() ?? {};
    final street = a['road'] ?? a['pedestrian'] ?? a['neighbourhood'] ?? a['suburb'];
    final house = a['house_number'];
    final name = m['name'] as String?;
    final parts = <String>[
      if (name != null && name.isNotEmpty && name != street) name,
      if (street != null) house != null ? '$street, $house' : street as String,
    ];
    if (parts.isEmpty) return (m['display_name'] as String? ?? '').split(',').take(2).join(',');
    return parts.join(' · ');
  }
}
