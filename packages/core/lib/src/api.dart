import 'dart:async';

import 'package:dio/dio.dart';

import 'config.dart';
import 'models.dart';
import 'token_store.dart';

/// Error with a message ready to show the user.
class ApiException implements Exception {
  ApiException(this.message, {this.code = '', this.status = 0});
  final String message;
  final String code;
  final int status;
  @override
  String toString() => message;
}

/// Typed client for the Nomo REST API. Refreshes the access token once on 401.
class ApiClient {
  ApiClient(this.tokens, {required this.onSignedOut, String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? NomoConfig.apiUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          contentType: 'application/json',
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        final t = tokens.access;
        if (t != null && o.extra['auth'] != false) o.headers['Authorization'] = 'Bearer $t';
        h.next(o);
      },
      onError: (e, h) async {
        final req = e.requestOptions;
        if (e.response?.statusCode == 401 && req.extra['retried'] != true && req.extra['auth'] != false && tokens.refresh != null) {
          if (await _refresh()) {
            req.extra['retried'] = true;
            req.headers['Authorization'] = 'Bearer ${tokens.access}';
            try {
              return h.resolve(await _dio.fetch(req));
            } on DioException catch (e2) {
              return h.next(e2);
            }
          }
          await tokens.clear();
          onSignedOut();
        }
        h.next(e);
      },
    ));
  }

  final TokenStore tokens;
  final void Function() onSignedOut;
  final Dio _dio;
  Future<bool>? _refreshing;

  Future<bool> _refresh() {
    return _refreshing ??= () async {
      try {
        final r = await _dio.post('/v1/auth/refresh',
            data: {'refresh_token': tokens.refresh}, options: Options(extra: {'auth': false}));
        final t = r.data['tokens'] as Map<String, dynamic>;
        await tokens.save(t['access_token'] as String, t['refresh_token'] as String);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<dynamic> _call(Future<Response<dynamic>> Function() f) async {
    try {
      return (await f()).data;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] is Map) {
        final err = data['error'] as Map;
        throw ApiException(err['message'] as String? ?? 'Ошибка', code: err['code'] as String? ?? '', status: e.response?.statusCode ?? 0);
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw ApiException('Нет связи с сервером. Проверьте интернет', code: 'offline');
      }
      throw ApiException('Что-то пошло не так, попробуйте ещё раз', status: e.response?.statusCode ?? 0);
    }
  }

  Future<dynamic> _get(String p, {Map<String, dynamic>? q}) => _call(() => _dio.get(p, queryParameters: q));
  Future<dynamic> _post(String p, [Object? body]) => _call(() => _dio.post(p, data: body));
  Future<dynamic> _put(String p, Object body) => _call(() => _dio.put(p, data: body));
  Future<dynamic> _patch(String p, Object body) => _call(() => _dio.patch(p, data: body));
  Future<dynamic> _delete(String p) => _call(() => _dio.delete(p));

  // ---- auth ----

  Future<int> requestCode(String phone, String role) async {
    try {
      final r = await _dio.post('/v1/auth/request-code',
          data: {'phone': phone, 'role': role}, options: Options(extra: {'auth': false}));
      return (r.data['resend_in'] as num?)?.toInt() ?? 60;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (e.response?.statusCode == 429 && data is Map) return (data['resend_in'] as num?)?.toInt() ?? 60;
      return await _call(() => Future.error(e)) as int;
    }
  }

  Future<void> verifyCode(String phone, String code, String role) async {
    final d = await _call(() => _dio.post('/v1/auth/verify',
        data: {'phone': phone, 'code': code, 'role': role}, options: Options(extra: {'auth': false})));
    final t = d['tokens'] as Map<String, dynamic>;
    await tokens.save(t['access_token'] as String, t['refresh_token'] as String);
  }

  Future<Me> me() async => Me.fromJson(await _get('/v1/me') as Map<String, dynamic>);
  Future<Me> updateMe({String? name, String? email, String? locale}) async => Me.fromJson(await _patch('/v1/me', {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (locale != null) 'locale': locale,
      }) as Map<String, dynamic>);
  Future<void> deleteAccount() => _delete('/v1/me');
  Future<void> savePushToken(String token, String platform) => _post('/v1/push-tokens', {'token': token, 'platform': platform});

  // ---- passenger ----

  /// [route] is the road route hint from [RoadRoute.toHint] (Yandex MapKit).
  Future<List<QuoteItem>> quote(Place from, Place to, {Map<String, dynamic>? route}) async => parseList(
      await _post('/v1/quotes', {'from': from.toJson(), 'to': to.toJson(), if (route != null) 'route': route}), QuoteItem.fromJson);

  Future<List<NearbyCar>> nearby(double lat, double lng) async =>
      parseList(await _get('/v1/drivers/nearby', q: {'lat': lat, 'lng': lng}), NearbyCar.fromJson);

  Future<Order> createOrder({
    required Place from,
    required Place to,
    required String tariff,
    required String paymentMethod,
    String? paymentMethodId,
    String comment = '',
    bool childSeat = false,
    bool withPet = false,
    Map<String, dynamic>? route,
  }) async =>
      Order.fromJson(await _post('/v1/orders', {
        if (route != null) 'route': route,
        'from': from.toJson(),
        'to': to.toJson(),
        'tariff': tariff,
        'payment_method': paymentMethod,
        if (paymentMethodId != null) 'payment_method_id': paymentMethodId,
        'comment': comment,
        'child_seat': childSeat,
        'with_pet': withPet,
      }) as Map<String, dynamic>);

  Future<Order?> activeOrder() async {
    final d = await _get('/v1/orders/active');
    return d == null ? null : Order.fromJson(d as Map<String, dynamic>);
  }

  Future<Order> order(String id) async => Order.fromJson(await _get('/v1/orders/$id') as Map<String, dynamic>);
  Future<List<Order>> history() async => parseList(await _get('/v1/orders'), Order.fromJson);
  Future<Order> cancelOrder(String id, {String reason = ''}) async =>
      Order.fromJson(await _post('/v1/orders/$id/cancel', {'reason': reason}) as Map<String, dynamic>);
  Future<void> rateDriver(String id, int rating, {String comment = ''}) =>
      _post('/v1/orders/$id/rate', {'rating': rating, 'comment': comment});
  Future<void> tip(String id, int amount) => _post('/v1/orders/$id/tip', {'amount': amount});

  Future<List<PaymentCard>> cards() async => parseList(await _get('/v1/payment-methods'), PaymentCard.fromJson);

  /// [token] comes from the acquirer's card tokenization page, never a raw card number.
  Future<PaymentCard> addCard({required String token, required String brand, required String last4}) async =>
      PaymentCard.fromJson(await _post('/v1/payment-methods', {'token': token, 'brand': brand, 'last4': last4}) as Map<String, dynamic>);
  Future<void> deleteCard(String id) => _delete('/v1/payment-methods/$id');

  Future<List<SavedPlace>> places() async => parseList(await _get('/v1/places'), SavedPlace.fromJson);
  Future<void> addPlace(String label, Place p) => _post('/v1/places', {'label': label, ...p.toJson()});
  Future<void> deletePlace(String id) => _delete('/v1/places/$id');

  // ---- chat & calls ----

  Future<List<ChatMessage>> messages(String orderId) async =>
      parseList(await _get('/v1/orders/$orderId/messages'), ChatMessage.fromJson);
  Future<ChatMessage> sendMessage(String orderId, String body) async =>
      ChatMessage.fromJson(await _post('/v1/orders/$orderId/messages', {'body': body}) as Map<String, dynamic>);
  Future<String> callNumber(String orderId) async => (await _get('/v1/orders/$orderId/call'))['phone'] as String;

  // ---- driver ----

  Future<DriverProfile> driverProfile() async => DriverProfile.fromJson(await _get('/v1/driver/profile') as Map<String, dynamic>);

  Future<DriverProfile> updateCar({
    required String name,
    required String make,
    required String model,
    required String color,
    required String plate,
    required int year,
  }) async =>
      DriverProfile.fromJson(await _put('/v1/driver/car', {
        'name': name,
        'car_make': make,
        'car_model': model,
        'car_color': color,
        'car_plate': plate,
        'car_year': year,
      }) as Map<String, dynamic>);

  Future<void> uploadDocument(String kind, String filePath) => _call(() => _dio.post('/v1/driver/documents',
      data: FormData.fromMap({'kind': kind, 'file': MultipartFile.fromFileSync(filePath)})));

  Future<DriverProfile> submitForReview() async => DriverProfile.fromJson(await _post('/v1/driver/submit') as Map<String, dynamic>);

  Future<DriverProfile> setOnline(bool online, {double? lat, double? lng}) async => DriverProfile.fromJson(
      await _post('/v1/driver/online', {'online': online, if (lat != null) 'lat': lat, if (lng != null) 'lng': lng}) as Map<String, dynamic>);

  Future<void> sendLocation(double lat, double lng, double heading) =>
      _post('/v1/driver/location', {'lat': lat, 'lng': lng, 'heading': heading});

  Future<Offer?> currentOffer() async {
    final d = await _get('/v1/driver/offer');
    return d == null ? null : Offer.fromJson(d as Map<String, dynamic>);
  }

  Future<Order> acceptOffer(String orderId) async =>
      Order.fromJson(await _post('/v1/driver/offers/$orderId/accept') as Map<String, dynamic>);
  Future<void> declineOffer(String orderId) => _post('/v1/driver/offers/$orderId/decline');

  Future<Order?> driverActiveOrder() async {
    final d = await _get('/v1/driver/orders/active');
    return d == null ? null : Order.fromJson(d as Map<String, dynamic>);
  }

  Future<List<Order>> driverHistory() async => parseList(await _get('/v1/driver/orders'), Order.fromJson);
  Future<Order> driverArrived(String id) async => Order.fromJson(await _post('/v1/driver/orders/$id/arrived') as Map<String, dynamic>);
  Future<Order> driverStart(String id) async => Order.fromJson(await _post('/v1/driver/orders/$id/start') as Map<String, dynamic>);
  Future<Order> driverComplete(String id) async => Order.fromJson(await _post('/v1/driver/orders/$id/complete') as Map<String, dynamic>);
  Future<void> driverCancel(String id) => _post('/v1/driver/orders/$id/cancel');
  Future<void> ratePassenger(String id, int rating) => _post('/v1/driver/orders/$id/rate', {'rating': rating});
  Future<Earnings> earnings() async => Earnings.fromJson(await _get('/v1/driver/earnings') as Map<String, dynamic>);
  Future<List<DemandCell>> demand() async => parseList(await _get('/v1/driver/demand'), DemandCell.fromJson);
}
