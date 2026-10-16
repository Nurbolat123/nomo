# Запуск и публикация Nomo

## 1. Что подключить перед запуском (в коде стоят заглушки)

| Что | Где в коде | Сейчас | Нужно |
| --- | --- | --- | --- |
| SMS-коды | `backend/internal/sms` | пишет код в лог | провайдер: Mobizon, SMSC.kz или Twilio — реализовать `sms.Sender` |
| Оплата картой | `backend/internal/payments` | тестовый провайдер | эквайринг (Halyk ePay, Kaspi Pay, CloudPayments…) — реализовать `payments.Provider`, в приложении открыть страницу привязки карты банка (`payment_methods_screen.dart`, TODO) |
| Звонки | `backend/internal/app/realtime.go` `CallProvider` | отдаёт настоящий номер | телефония с подменными номерами (Zadarma, Mango Office) |
| Push | `backend/internal/push` | лог; FCM готов | создать проект Firebase, задать `FCM_PROJECT_ID` и `FCM_SERVICE_ACCOUNT_JSON`; в приложения добавить `firebase_messaging` и отправку токена в `POST /v1/push-tokens` |
| Карты и маршруты | `packages/core/lib/src/map/` | Яндекс MapKit при наличии ключа, иначе OpenStreetMap и прямые линии | ключ MapKit (см. раздел «Яндекс Карты» ниже) |
| Адреса | `packages/core/lib/src/geocoding.dart` | Nominatim (OSM) | Яндекс Геокодер/Саджест из MapKit — реализовать `Geocoder` |

## Яндекс Карты (MapKit)

Карта, маршруты по дорогам, плавное движение машины и траектория работают на Яндекс MapKit.

1. Зайдите в [кабинет разработчика](https://developer.tech.yandex.ru/) → «Подключить API» → **MapKit — мобильный SDK**.
   Ключ активируется примерно через 15 минут.
2. Бесплатно — до 1 000 активных пользователей в день; дальше годовой тариф Яндекса
   ([цены](https://yandex.ru/dev/tariffs/doc/ru/mapkit/prices/)). Для такси прочитайте
   [оферту Maps API](https://yandex.ru/legal/maps_api_offer) или уточните у Яндекса условия коммерческого использования.
3. Передайте ключ при запуске и сборке (в git его не кладите):
   ```bash
   flutter run --dart-define=YANDEX_MAPKIT_KEY=ваш_ключ --dart-define=API_URL=http://192.168.1.10:8080
   ```
   В GitHub: Settings → Secrets and variables → Actions → секрет `YANDEX_MAPKIT_KEY` (и переменная `API_URL`) —
   тогда CI соберёт APK с картами, скачать их можно во вкладке Actions → Artifacts.
4. Без ключа приложения работают на OpenStreetMap с прямыми линиями вместо маршрутов — удобно для разработки.

Как устроено: маршрут строит приложение через MapKit (`YandexRouteService`) и отправляет его на сервер
вместе с заказом; сервер проверяет, что маршрут правдоподобный, считает по нему цену и хранит его в заказе.
Для сборки Android нужен JDK 21 (идёт с Android Studio).

## 2. Сервер

1. Арендуйте сервер (2 vCPU, 4 ГБ хватит на старт), установите Docker.
2. Скопируйте `backend/.env.example` в `backend/.env`, задайте `JWT_SECRET` (`openssl rand -hex 32`),
   `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `PUBLIC_URL`.
3. `docker compose up -d` в корне проекта.
4. Поставьте перед API обратный прокси с HTTPS (Caddy или Nginx + Let's Encrypt) на домен, например `api.nomo.kz`.
   WebSocket идёт по `/v1/ws` — включите проксирование Upgrade.
5. Админка: `cd admin && VITE_API_URL=https://api.nomo.kz npm run build`, папку `admin/dist` раздайте как статический сайт.
6. Опубликуйте политику конфиденциальности (`docs/legal/privacy-policy.md`) и условия на сайте,
   страница удаления аккаунта уже есть: `https://api.nomo.kz/delete-account`.

## 3. Приложения

```bash
./tool/setup_native.sh                     # один раз: iOS/Android проекты, иконки, сплэш
cd apps/passenger
flutter run --dart-define=API_URL=http://192.168.1.10:8080   # IP вашего компьютера
```

### Android: ключ подписи

```bash
keytool -genkey -v -keystore ~/nomo-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Создайте `apps/<app>/android/key.properties` (не коммитить):

```
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=/Users/you/nomo-upload.jks
```

### Сборка и загрузка

```bash
cd apps/passenger
export API_URL=https://api.nomo.kz PRIVACY_URL=https://nomo.kz/privacy TERMS_URL=https://nomo.kz/terms
fastlane android beta     # Google Play, внутреннее тестирование
fastlane ios beta         # TestFlight
```

## 4. Чек-лист перед отправкой на проверку

- [ ] `DEMO_MODE=true` на сервере, демо-номера работают (см. `docs/store/listing.md`)
- [ ] Реальные SMS и эквайринг подключены, тестовая карта в релизе не появляется
- [ ] Политика, условия и страница удаления аккаунта открываются по HTTPS
- [ ] Иконки и сплэш сгенерированы, название «Nomo» / «Nomo Driver»
- [ ] Data safety и App Privacy заполнены по `docs/store/data-safety.md`
- [ ] Google Play: декларация Foreground service (location) с видео — для Nomo Driver
- [ ] Новый личный аккаунт Google Play: закрытое тестирование 12+ тестировщиков 14 дней
- [ ] Полный цикл поездки пройден на реальных iPhone и Android
- [ ] Казахские переводы проверены носителем языка (`packages/core/lib/src/strings.dart`)
