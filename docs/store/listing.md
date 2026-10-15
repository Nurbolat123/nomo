# Тексты для карточек в App Store и Google Play

Лимиты: App Store — название 30, подзаголовок 30, ключевые слова 100 символов, описание 4000.
Google Play — название 30, краткое описание 80, полное 4000.

## Nomo (пассажир)

| Поле | Русский | English |
| --- | --- | --- |
| Название | Nomo — такси | Nomo — Taxi |
| Подзаголовок (iOS) | Такси за пару касаний | Rides in a couple of taps |
| Краткое описание (Play) | Закажите такси за пару касаний: цена заранее, машина на карте | Book a ride in a couple of taps: upfront price, live car on the map |
| Ключевые слова (iOS) | такси,заказ такси,поездка,водитель,трансфер,аэропорт,уральск,казахстан,такси онлайн | taxi,ride,cab,driver,transfer,airport,kazakhstan,uralsk,booking |
| Категория | Путешествия (iOS) / Карты и навигация (Play) | Travel / Maps & Navigation |
| Возрастной рейтинг | 4+ / Для всех | 4+ / Everyone |

**Полное описание (RU)**

Nomo — сервис заказа такси. Укажите, куда едем, — цена известна заранее и не изменится в пути.

• Цена до заказа: подача, километры и минуты уже посчитаны
• Тарифы Эконом, Комфорт и Бизнес
• Машина на карте в реальном времени и время подачи
• Звонок и чат с водителем прямо в приложении
• Оплата картой или наличными, чаевые водителю
• Кнопка SOS и «поделиться поездкой» с близкими
• Сохранённые адреса: дом, работа, любимые места
• История поездок и чеки

Move like a nomad.

**Full description (EN)**

Nomo is a ride-hailing app. Tell us where you are going and see the price before you book — it will not change on the way.

• Upfront price with pickup, distance and time included
• Economy, Comfort and Business rides
• Live car on the map and pickup time
• Call or chat with your driver in the app
• Pay by card or cash, tip your driver
• SOS button and trip sharing with family
• Saved places: home, work, favorites
• Trip history and receipts

## Nomo Driver

| Поле | Русский | English |
| --- | --- | --- |
| Название | Nomo Driver | Nomo Driver |
| Подзаголовок (iOS) | Заказы такси рядом с вами | Ride requests near you |
| Краткое описание (Play) | Принимайте заказы Nomo, следите за заработком и выходите на линию когда удобно | Accept Nomo rides, track earnings and go online whenever you like |
| Категория | Бизнес (iOS) / Карты и навигация (Play) | Business / Maps & Navigation |

**Полное описание (RU)**

Приложение для водителей Nomo.

• Регистрация за 10 минут: данные машины и фото документов
• Выходите на линию, когда удобно
• Ближайшие заказы с ценой, расстоянием и способом оплаты
• Навигация через 2ГИС, Яндекс Навигатор или Google Maps
• Карта спроса — где сейчас больше заказов
• Заработок за день и неделю, комиссия и баланс

Местоположение передаётся только пока вы на линии.

## Скриншоты

Нужны размеры: iPhone 6.9" (1320×2868) и 6.5" (1284×2778), Android телефон (1080×1920 и выше).
Снимайте на демо-аккаунте (см. ниже), 5–6 кадров на приложение:

1. Главный экран с картой и полем «Куда едем?»
2. Выбор тарифа с ценами
3. Поиск водителя
4. Водитель едет: карточка машины, звонок, чат
5. Оценка поездки
6. (Driver) Новый заказ с таймером; заработок за день

Сверху на каждом кадре — крупная подпись в 3–5 слов на чёрном фоне, акцент золотом #FFC93C.

## Заметки для ревьюера (App Review Information / Play «Доступ к приложению»)

```
Demo account (passenger app):
  Phone: +7 700 000 00 00
  SMS code: 0000
After you order a ride, a demo driver accepts it within a few seconds,
drives to the pickup, starts and completes the trip automatically (~1 minute),
so the whole flow including rating can be checked.

Demo account (driver app):
  Phone: +7 700 000 00 01
  SMS code: 0000
The demo driver is already approved and can go online.

Location is used only to set the pickup point (passenger) and,
while the driver is online, to dispatch nearby orders (driver).
Account deletion: Profile → Delete account.
```

Демо-режим включается на сервере переменной `DEMO_MODE=true` (см. backend/.env.example).
