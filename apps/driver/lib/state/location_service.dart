import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Streams the driver's position while online.
///
/// Android: a foreground service with a persistent "You are online"
/// notification keeps updates coming with the screen off; only
/// "while in use" permission is needed, so no background-location
/// declaration is required on Google Play.
/// iOS: background mode "location" with the blue status-bar indicator.
class LocationService {
  StreamSubscription<Position>? _sub;
  final _positions = StreamController<Position>.broadcast();

  Stream<Position> get positions => _positions.stream;
  bool get running => _sub != null;

  /// Asks for "while in use" permission. Returns false if refused.
  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
      if (!await Geolocator.isLocationServiceEnabled()) return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  static LocationSettings _settings({required String title, required String text}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: title,
          notificationText: text,
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 8,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 8);
  }

  void start({required String title, required String text}) {
    if (_sub != null) return;
    _sub = Geolocator.getPositionStream(locationSettings: _settings(title: title, text: text)).listen(
      _positions.add,
      onError: (_) {},
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  static Future<Position?> current() async {
    try {
      return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }
}
