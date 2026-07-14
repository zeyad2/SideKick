import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Network reachability, behind an interface so sync is stub-able in tests.
abstract interface class ConnectivityService {
  /// `true` when the device currently has some network transport.
  Future<bool> isConnected();

  /// Emits `true` when connectivity is (re)gained, `false` when lost.
  Stream<bool> get onConnectedChanged;
}

class ConnectivityPlusService implements ConnectivityService {
  ConnectivityPlusService([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((ConnectivityResult r) => r != ConnectivityResult.none);

  @override
  Future<bool> isConnected() async =>
      _isOnline(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onConnectedChanged =>
      _connectivity.onConnectivityChanged.map(_isOnline);
}
