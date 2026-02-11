import 'package:connectivity_plus/connectivity_plus.dart';

Future<bool> hasNetworkInterface() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.any((value) => value != ConnectivityResult.none);
  } catch (_) {
    // Missing plugin or runtime errors should not hard-fail connectivity.
    return true;
  }
}
