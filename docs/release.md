# Запуск и публикация Nomo

## 1. Что подключить перед запуском (в коде стоят заглушки)

| Что | Где в коде | Сейчас | Нужно |
| --- | --- | --- | --- |
| SMS-коды | `backend/internal/sms` | пишет код в лог | провайдер: Mobizon, SMSC.kz или Twilio — реализовать `sms.Sender` |
| Оплата картой | `backend/internal/payments` | тестовый провайдер | эквайринг (Halyk ePay, Kaspi Pay, CloudPayments…) — реализовать `payments.Provider`, в приложении открыть страницу привязки карты банка (`payment_methods_screen.dart`, TODO) |
| Звонки | `backend/internal/app/realtime.go` `CallProvider` | отдаёт настоящий номер | телефония с подменными номерами (Zadarma, Mango Office) |
| Push | `backend/internal/push` | лог; FCM готов | создать проект Firebase, задать `FCM_PROJECT_ID` и `FCM_SERVICE_ACCOUNT_JSON`; в приложения добавить `firebase_messaging` и отправку токена в `POST /v1/push-tokens` |
| Карты | `packages/core/lib/src/widgets/nomo_map.dart` | тайлы OpenStreetMap | тайлы 2GIS/MapTiler с ключом (`--dart-define=TILE_URL=…`) |
| Адреса | `packages/core/lib/src/geocoding.dart` | Nominatim (OSM) | 2GIS Catalog API или Яндекс Геокодер — реализовать `Geocoder` |
| Маршрут и время | `backend/internal/geo` | прямая × 1,35, 28 км/ч | Routing API 2GIS / Яндекс — для точной цены и времени подачи |

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
