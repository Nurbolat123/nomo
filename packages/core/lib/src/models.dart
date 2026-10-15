// Data models mirroring the backend JSON.

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();
int? _in(dynamic v) => v == null ? null : (v as num).toInt();
String _s(dynamic v) => v == null ? '' : v as String;
DateTime? _t(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    v == null ? <T>[] : (v as List).map((e) => f(e as Map<String, dynamic>)).toList();

class Place {
  const Place({required this.lat, required this.lng, this.addr = ''});
  final double lat;
  final double lng;
  final String addr;

  factory Place.fromJson(Map<String, dynamic> j) => Place(lat: _d(j['lat']), lng: _d(j['lng']), addr: _s(j['addr']));
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'addr': addr};
  Place copyWith({String? addr}) => Place(lat: lat, lng: lng, addr: addr ?? this.addr);
}

class DriverCard {
  DriverCard.fromJson(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        rating = _d(j['rating']),
        carMake = _s(j['car_make']),
        carModel = _s(j['car_model']),
        carColor = _s(j['car_color']),
        carPlate = _s(j['car_plate']);
  final String id, name, carMake, carModel, carColor, carPlate;
  final double rating;
  String get car => '$carColor $carMake $carModel'.trim();
}

class PassengerCard {
  PassengerCard.fromJson(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        rating = _d(j['rating']);
  final String id, name;
  final double rating;
}

enum OrderStatus { searching, assigned, arrived, inProgress, completed, cancelled, noDrivers }

OrderStatus parseStatus(String s) => switch (s) {
      'searching' => OrderStatus.searching,
      'assigned' => OrderStatus.assigned,
      'arrived' => OrderStatus.arrived,
      'in_progress' => OrderStatus.inProgress,
      'completed' => OrderStatus.completed,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.noDrivers,
    };

class Order {
  Order.fromJson(Map<String, dynamic> j)
      : id = _s(j['id']),
        passengerId = _s(j['passenger_id']),
        driverId = j['driver_id'] as String?,
        tariff = _s(j['tariff']),
        status = parseStatus(_s(j['status'])),
        from = Place.fromJson(j['from'] as Map<String, dynamic>),
        to = Place.fromJson(j['to'] as Map<String, dynamic>),
        distanceM = _i(j['distance_m']),
        durationS = _i(j['duration_s']),
        surge = _d(j['surge']),
        price = _i(j['price']),
        finalPrice = _in(j['final_price']),
        tip = _i(j['tip']),
        paymentMethod = _s(j['payment_method']),
        paymentStatus = _s(j['payment_status']),
        comment = _s(j['comment']),
        cancelledBy = _s(j['cancelled_by']),
        cancelFee = _i(j['cancel_fee']),
        driverRating = _in(j['driver_rating']),
        passengerRating = _in(j['passenger_rating']),
        createdAt = _t(j['created_at'])!,
        assignedAt = _t(j['assigned_at']),
        arrivedAt = _t(j['arrived_at']),
        startedAt = _t(j['started_at']),
        completedAt = _t(j['completed_at']),
        currency = _s(j['currency']),
        driver = j['driver'] == null ? null : DriverCard.fromJson(j['driver'] as Map<String, dynamic>),
        passenger = j['passenger'] == null ? null : PassengerCard.fromJson(j['passenger'] as Map<String, dynamic>);

  final String id, passengerId, tariff, paymentMethod, paymentStatus, comment, cancelledBy, currency;
  final String? driverId;
  final OrderStatus status;
  final Place from, to;
  final int distanceM, durationS, price, tip, cancelFee;
  final int? finalPrice, driverRating, passengerRating;
  final double surge;
  final DateTime createdAt;
  final DateTime? assignedAt, arrivedAt, startedAt, completedAt;
  final DriverCard? driver;
  final PassengerCard? passenger;

  bool get isActive =>
      status == OrderStatus.searching ||
      status == OrderStatus.assigned ||
      status == OrderStatus.arrived ||
      status == OrderStatus.inProgress;

  int get total => (finalPrice ?? price) + tip;
}

class QuoteItem {
  QuoteItem.fromJson(Map<String, dynamic> j)
      : tariff = _s(j['tariff']),
        name = _s(j['name']),
        price = _i(j['price']),
        surge = _d(j['surge']),
        etaS = _in(j['eta_s']),
        distanceM = _i(j['distance_m']),
        durationS = _i(j['duration_s']);
  final String tariff, name;
  final int price, distanceM, durationS;
  final int? etaS;
  final double surge;
}

class Offer {
  Offer.fromJson(Map<String, dynamic> j)
      : orderId = _s(j['order_id']),
        tariff = _s(j['tariff']),
        from = Place.fromJson(j['from'] as Map<String, dynamic>),
        to = Place.fromJson(j['to'] as Map<String, dynamic>),
        price = _i(j['price']),
        distanceM = _i(j['distance_m']),
        durationS = _i(j['duration_s']),
        pickupDistanceM = _i(j['pickup_distance_m']),
        pickupEtaS = _i(j['pickup_eta_s']),
        paymentMethod = _s(j['payment_method']),
        passengerRating = _d(j['passenger_rating']),
        comment = _s(j['comment']),
        childSeat = j['child_seat'] == true,
        withPet = j['with_pet'] == true,
        expiresAt = _t(j['expires_at'])!;
  final String orderId, tariff, paymentMethod, comment;
  final Place from, to;
  final int price, distanceM, durationS, pickupDistanceM, pickupEtaS;
  final double passengerRating;
  final bool childSeat, withPet;
  final DateTime expiresAt;
}

class PaymentCard {
  PaymentCard.fromJson(Map<String, dynamic> j)
      : id = _s(j['id']),
        brand = _s(j['brand']),
        last4 = _s(j['last4']);
  final String id, brand, last4;
  String get label => '${brand.toUpperCase()} •• $last4';
}

class SavedPlace {
  SavedPlace.fromJson(Map<String, dynamic> j)
      : id = _s(j['id']),
        label = _s(j['label']),
        place = Place(lat: _d(j['lat']), lng: _d(j['lng']), addr: _s(j['addr']));
  final String id, label;
  final Place place;
}

class ChatMessage {
  ChatMessage.fromJson(Map<String, dynamic> j)
      : id = _i(j['id']),
        orderId = _s(j['order_id']),
        senderId = _s(j['sender_id']),
        body = _s(j['body']),
        createdAt = _t(j['created_at'])!;
  final int id;
  final String orderId, senderId, body;
  final DateTime createdAt;
}

class Me {
  Me.fromJson(Map<String, dynamic> j)
      : id = _s(j['id']),
        phone = _s(j['phone']),
        role = _s(j['role']),
        name = _s(j['name']),
        email = _s(j['email']),
        locale = _s(j['locale']),
        rating = _d(j['rating']);
  final String id, phone, role, name, email, locale;
  final double rating;
}

class DriverDocument {
  DriverDocument.fromJson(Map<String, dynamic> j)
      : id = _s(j['id']),
        kind = _s(j['kind']),
        createdAt = _t(j['created_at']);
  final String id, kind;
  final DateTime? createdAt;
}

class DriverProfile {
  DriverProfile.fromJson(Map<String, dynamic> j)
      : id = _s(j['id']),
        phone = _s(j['phone']),
        name = _s(j['name']),
        rating = _d(j['rating']),
        status = _s(j['status']),
        statusNote = _s(j['status_note']),
        carMake = _s(j['car_make']),
        carModel = _s(j['car_model']),
        carColor = _s(j['car_color']),
        carPlate = _s(j['car_plate']),
        carYear = _i(j['car_year']),
        classes = (j['classes'] as List? ?? const []).cast<String>(),
        online = j['online'] == true,
        busy = j['busy'] == true,
        balance = _i(j['balance']),
        documents = _list(j['documents'], DriverDocument.fromJson);
  final String id, phone, name, status, statusNote, carMake, carModel, carColor, carPlate;
  final int carYear, balance;
  final double rating;
  final List<String> classes;
  final bool online, busy;
  final List<DriverDocument> documents;

  bool get approved => status == 'approved';
  bool hasDoc(String kind) => documents.any((d) => d.kind == kind);
}

class EarningsPeriod {
  EarningsPeriod.fromJson(Map<String, dynamic> j)
      : trips = _i(j['trips']),
        earned = _i(j['earned']),
        cash = _i(j['cash']),
        card = _i(j['card']),
        tips = _i(j['tips']),
        commission = _i(j['commission']);
  final int trips, earned, cash, card, tips, commission;
}

class Earnings {
  Earnings.fromJson(Map<String, dynamic> j)
      : today = EarningsPeriod.fromJson(j['today'] as Map<String, dynamic>),
        week = EarningsPeriod.fromJson(j['week'] as Map<String, dynamic>),
        balance = _i(j['balance']);
  final EarningsPeriod today, week;
  final int balance;
}

class NearbyCar {
  NearbyCar.fromJson(Map<String, dynamic> j)
      : lat = _d(j['lat']),
        lng = _d(j['lng']),
        heading = _d(j['heading']);
  final double lat, lng, heading;
}

class DemandCell {
  DemandCell.fromJson(Map<String, dynamic> j)
      : lat = _d(j['lat']),
        lng = _d(j['lng']),
        orders = _i(j['orders']),
        level = _i(j['level']);
  final double lat, lng;
  final int orders, level;
}

List<T> parseList<T>(dynamic data, T Function(Map<String, dynamic>) f) => _list(data, f);
