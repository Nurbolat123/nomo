# Nomo — инструкция для Claude Code

Сервис заказа такси Nomo: приложение пассажира, приложение водителя, веб-админка и бэкенд.
Оба приложения публикуются в App Store и Google Play. MVP уже написан — дальше доводка и запуск.

## Бренд

- Название: **Nomo** (пассажир), **Nomo Driver** (водитель). Слоган: «Move like a nomad.»
- Цвета: чёрный `#0A0A0A`, белый, акцент золото `#FFC93C`. Один акцент, без градиентов.
- Знак: купол юрты в форме буквы «n» с золотой точкой (`NomoMark` в `packages/core`, генератор иконок `tool/make_icons.py`).
- Bundle ID / applicationId: `com.nomo.passenger`, `com.nomo.driver`.

## Как работать

- Перед изменением покажи короткий план (5–10 пунктов) и жди подтверждения, если задача больше пары файлов.
- В конце: что сделано, какие файлы изменены, что проверить вручную, команды запуска.
- Неясное — спрашивай. Не придумывай ключи, домены и реквизиты.
- Новые зависимости — только с объяснением.
- Перед коммитом: `go vet` + `go test` (бэкенд), `flutter analyze` + `flutter test` (приложения), `npm run build` (админка).
- Коммиты маленькие, на английском: `feat: …`, `fix: …`.
- Секреты только в `.env` и CI secrets. `.env`, `key.properties`, keystore, `*.p8`, `google-services.json` — в `.gitignore`.
- Тексты для пользователя — через `S.of(context).t('key')` (`packages/core/lib/src/strings.dart`), ru/kk/en.

## Стек

| Часть | Технологии |
| --- | --- |
| Приложения | Flutter 3.27+, Riverpod 2, go_router, dio, flutter_map (OSM-тайлы, заменяемые), geolocator |
| Общий пакет | `packages/core`: модели, `ApiClient`, `RealtimeClient` (WebSocket), тема, переводы, карта, вход, чат, настройки |
| Бэкенд | Go 1.24 (stdlib net/http), PostgreSQL 16, Redis (GEO для водителей), coder/websocket, JWT |
| Админка | React 18 + TypeScript + Vite + Leaflet |
| Публикация | fastlane (`apps/*/fastlane`), `tool/setup_native.sh`, `tool/patch_native.py` |

## Структура

```
apps/passenger   lib/state/ride_controller.dart — вся логика поездки; screens/, widgets/ — экраны и панели
apps/driver      lib/state/driver_controller.dart, location_service.dart; screens/, widgets/
packages/core    lib/src/ — api, models, realtime, providers, theme, strings, geocoding, widgets/
backend          cmd/api — запуск; internal/app — HTTP, диспетчеризация, демо; pricing, geo, auth, payments, sms, push, realtime, db
admin            src/pages — Обзор, Водители, Заказы, Тарифы
docs             api.md, release.md, store/, legal/
tool             setup_native.sh, patch_native.py, make_icons.py
```

Нативные папки `ios/` и `android/` создаёт `tool/setup_native.sh` (flutter create + патч разрешений,
Info.plist, PrivacyInfo, minSdk 28, iOS 16, подпись релиза). Правки для сторов вносить в `tool/patch_native.py`,
а не вручную в сгенерированные файлы.

## Ключевые решения

- Статусы заказа: `searching → assigned → arrived → in_progress → completed` / `cancelled` / `no_drivers`.
- Диспетчеризация: ближайший свободный водитель получает предложение на 15 с, затем следующий; радиус 2 → 4 → 7 км; 3 минуты поиска.
- Цена фиксируется при заказе; к ней добавляется только платное ожидание.
- Карта: при наличной оплате с баланса водителя списывается комиссия; при карточной — начисляется сумма минус комиссия.
- Геолокация водителя: только «во время использования» + foreground service (Android) / background mode (iOS), пока водитель на линии.
- Демо-режим (`DEMO_MODE`): номер `+77000000000`, код `0000` — заказ выполняет бот-водитель. Нужен ревьюерам сторов.
- Realtime-хаб в памяти процесса: для нескольких экземпляров API перевести на Redis pub/sub.

## Что осталось до запуска (подробно — docs/release.md)

1. SMS-провайдер (`sms.Sender`), эквайринг (`payments.Provider` + страница привязки карты в приложении).
2. Firebase: `firebase_messaging` в приложениях, отправка токена в `POST /v1/push-tokens`.
3. Коммерческие карты и геокодер (2GIS/Яндекс), Routing API для точных цены и времени подачи.
4. Телефония с подменными номерами (`CallProvider`).
5. Шрифт Manrope в `assets/fonts` и `NomoTheme.fontFamily`.
6. Проверка казахских переводов, скриншоты, публикация политики и условий.
7. Sentry для приложений и бэкенда.
