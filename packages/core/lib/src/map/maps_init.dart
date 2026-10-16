import 'package:yandex_maps_mapkit/init.dart' as ymi;

import '../config.dart';

/// Call once in main() before runApp. Does nothing without a Yandex key.
Future<void> initMaps({String locale = 'ru_RU'}) async {
  if (!NomoConfig.hasYandexMaps) return;
  await ymi.initMapkit(apiKey: NomoConfig.yandexKey, locale: locale);
}
