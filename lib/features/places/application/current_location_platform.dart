import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class CurrentCoordinates {
  const CurrentCoordinates({required this.lat, required this.lng});

  final double lat;
  final double lng;
}

class CurrentLocationPlatform {
  const CurrentLocationPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.sidekick/reminders');

  final MethodChannel _channel;

  Future<CurrentCoordinates> getCurrent() async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('Current location is only available on Android.');
    }
    final Map<Object?, Object?>? value = await _channel
        .invokeMapMethod<Object?, Object?>('currentLocation');
    final num? lat = value?['lat'] as num?;
    final num? lng = value?['lng'] as num?;
    if (lat == null || lng == null) {
      throw const FormatException('Current location was unavailable.');
    }
    return CurrentCoordinates(lat: lat.toDouble(), lng: lng.toDouble());
  }
}
