import 'package:flutter_test/flutter_test.dart';
import 'package:nomo_core/nomo_core.dart';

void main() {
  test('money groups thousands with a narrow space and tenge sign', () {
    expect(money(1200), '1 200 ₸');
    expect(money(950), '950 ₸');
    expect(money(1234567), '1 234 567 ₸');
    expect(money(-300), '−300 ₸');
  });

  test('minutes rounds up and is at least 1', () {
    expect(minutes(30), '1 мин');
    expect(minutes(61), '2 мин');
  });

  test('distance switches to km', () {
    expect(distance(850), '850 м');
    expect(distance(4200), '4,2 км');
  });

  test('prettyPhone formats Kazakhstan numbers', () {
    expect(prettyPhone('+77011112233'), '+7 701 111 22 33');
  });

  test('Order parses backend JSON', () {
    final o = Order.fromJson({
      'id': 'o1',
      'passenger_id': 'p1',
      'driver_id': null,
      'tariff': 'economy',
      'status': 'in_progress',
      'from': {'lat': 51.2, 'lng': 51.3, 'addr': 'A'},
      'to': {'lat': 51.1, 'lng': 51.4, 'addr': 'B'},
      'distance_m': 5000,
      'duration_s': 600,
      'surge': 1.2,
      'price': 1100,
      'final_price': null,
      'tip': 0,
      'payment_method': 'cash',
      'payment_status': 'none',
      'comment': '',
      'cancelled_by': '',
      'cancel_fee': 0,
      'driver_rating': null,
      'passenger_rating': null,
      'created_at': '2026-10-16T10:00:00Z',
      'currency': 'KZT',
    });
    expect(o.status, OrderStatus.inProgress);
    expect(o.isActive, isTrue);
    expect(o.total, 1100);
  });

  test('strings fall back to Russian', () {
    expect(S('kk').t('where_to'), 'Қайда барамыз?');
    expect(S('kk').t('searching_hint'), S('ru').t('searching_hint'));
    expect(S('en').f('order_tariff', {'tariff': 'Economy'}), 'Order Economy');
  });
}
