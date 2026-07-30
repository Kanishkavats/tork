import 'dart:async';

class LocationService {
  Stream<Map<String, double>> getTrackedLocation() async* {
    double lat = 37.7749;
    double lng = -122.4194;
    while (true) {
      await Future.delayed(const Duration(seconds: 2));
      lat += 0.0001;
      lng += 0.0001;
      yield {'latitude': lat, 'longitude': lng};
    }
  }

  Future<Map<String, double>> getCurrentLocation() async {
    return {'latitude': 37.7749, 'longitude': -122.4194};
  }
}
