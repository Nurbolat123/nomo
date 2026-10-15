# Nomo

Сервис заказа такси: приложение пассажира, приложение водителя, веб-админка и бэкенд.

| Часть | Папка | Стек |
| --- | --- | --- |
| Приложение пассажира | `apps/passenger` | Flutter |
| Приложение водителя | `apps/driver` | Flutter |
| Общий код приложений | `packages/core` | Dart: API, WebSocket, тема, переводы, карта, вход, чат |
| Бэкенд | `backend` | Go, PostgreSQL, Redis, WebSocket |
| Админка | `admin` | React + TypeScript + Leaflet |
| Документы | `docs` | API, публикация, тексты для сторов, политика |

## Быстрый старт

Нужно: Docker, Go 1.24, Node 22, Flutter 3.27+ (для iOS — Mac с Xcode).

```bash
# 1. База, Redis и API
docker compose up -d            # API на http://localhost:8080

# 2. Админка — http://localhost:5173, вход admin@nomo.local / admin
cd admin && npm install && npm run dev

# 3. Приложения (один раз создаёт iOS/Android проекты, иконки и сплэш)
./tool/setup_native.sh
cd apps/passenger && flutter run --dart-define=API_URL=http://<IP компьютера>:8080
cd apps/driver    && flutter run --dart-define=API_URL=http://<IP компьютера>:8080
```

Войти без SMS: в режиме разработки код пишется в лог API (`docker compose logs -f api`).
Демо-номера: пассажир `+7 700 000 00 00`, водитель `+7 700 000 00 01`, код `0000` —
заказ с демо-пассажира выполняет бот-водитель (так проверяют ревьюеры App Store и Google Play).

Как стать водителем локально: войдите в приложение водителя, заполните машину, загрузите 5 фото,
отправьте на проверку и одобрите в админке → «Водители».

## Тесты

```bash
docker compose exec postgres createdb -U nomo nomo_test   # один раз
cd backend && TEST_DATABASE_URL=postgres://nomo:nomo@localhost:5432/nomo_test?sslmode=disable go test -p 1 ./...
cd admin && npm run build
cd packages/core && flutter test
```

Полный цикл поездки (вход, регистрация водителя, заказ, предложение, принятие, чат, статусы, оплата картой,
оценка, чаевые, заработок), отмены, «нет машин», передача заказа следующему водителю и удаление аккаунта
проверяются интеграционными тестами бэкенда.

## Дальше

- `docs/release.md` — что подключить перед запуском (SMS, эквайринг, карты) и как выложить в сторы
- `docs/store/` — тексты карточек, заметки для ревьюера, анкеты Data safety / App Privacy
- `docs/api.md` — все методы API и события WebSocket
- `CLAUDE.md` — инструкции для Claude Code
