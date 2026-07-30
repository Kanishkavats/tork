import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../common/constants/api_constants.dart';

class RideService {
  static const String baseUrl = '${ApiConstants.baseUrl}/api';

  static Future<Map<String, dynamic>> estimateRide({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    required String vehicle,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ride/estimate'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'drop_lat': dropLat,
        'drop_lng': dropLng,
        'vehicle': vehicle,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to estimate ride');
  }

  static Future<Map<String, dynamic>> requestRide({
    required String phone,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double dropLat,
    required double dropLng,
    required String dropAddress,
    required String vehicle,
    required double distanceKm,
    required double fare,
    required int malePassengers,
    required int femalePassengers,
  }) async {
    final requestUrl = '$baseUrl/ride/request';
    final requestBody = json.encode({
      'phone': phone,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'pickup_address': pickupAddress,
      'drop_lat': dropLat,
      'drop_lng': dropLng,
      'drop_address': dropAddress,
      'vehicle': vehicle,
      'distance_km': distanceKm,
      'fare': fare,
      'male_passengers': malePassengers,
      'female_passengers': femalePassengers,
    });

    print('Ride Request DEBUG: Hitting URL: $requestUrl');
    print('Ride Request DEBUG: Request Body: $requestBody');

    try {
      final response = await http.post(
        Uri.parse(requestUrl),
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      print('Ride Request DEBUG: Status Code: ${response.statusCode}');
      print('Ride Request DEBUG: Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'ride_id': data['ride_id'], 'pickup_otp': data['pickup_otp']};
      }
      throw Exception('Failed to request ride: Status ${response.statusCode}, Body: ${response.body}');
    } catch (e) {
      print('Ride Request DEBUG: Exception occurred: $e');
      rethrow;
    }
  }

  // TEMP: Disabled for customer-only delivery.
  // static Future<void> matchDriver(int rideId) async {
  //   final response = await http.post(
  //     Uri.parse('$baseUrl/ride/match'),
  //     headers: {'Content-Type': 'application/json'},
  //     body: json.encode({'ride_id': rideId}),
  //   );
  //   if (response.statusCode != 200) {
  //     throw Exception('Failed to match driver');
  //   }
  // }

  static Future<Map<String, dynamic>> getRideStatus(int rideId) async {
    final response = await http.get(Uri.parse('$baseUrl/ride/status?ride_id=$rideId'));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to get ride status');
  }

  static Future<void> savePayment({
    required int rideId,
    required String transactionId,
    required String upiId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ride/payment'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'ride_id': rideId,
        'transaction_id': transactionId,
        'upi_id': upiId,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to save payment details: ${response.body}');
    }
  }

  static Future<void> triggerSOS({
    int? rideId,
    required String phone,
    required double lat,
    required double lng,
  }) async {
    final body = {
      'phone': phone,
      'lat': lat,
      'lng': lng,
    };
    if (rideId != null) body['ride_id'] = rideId;
    
    final response = await http.post(
      Uri.parse('$baseUrl/sos'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to trigger SOS');
    }
  }

  static Future<List<dynamic>> getHistory(String phone) async {
    final response = await http.get(Uri.parse('$baseUrl/ride/history?phone=$phone'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['history'] ?? [];
    }
    throw Exception('Failed to fetch history');
  }
}

class UserService {
  static const String baseUrl = '${ApiConstants.baseUrl}/api';

  static Future<void> updateCurrentLocation({
    required String phone,
    required double latitude,
    required double longitude,
    required String address,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/users/current-location'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'phone': phone,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update live location: ${response.statusCode}');
    }
  }

  static Future<List<dynamic>> getEmergencyContacts(String phone) async {
    final response = await http.get(Uri.parse('$baseUrl/contacts?phone=$phone'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['contacts'] ?? [];
    }
    throw Exception('Failed to fetch emergency contacts');
  }

  static Future<void> saveEmergencyContacts(String phone, List<Map<String, String>> contacts) async {
    final response = await http.post(
      Uri.parse('$baseUrl/contacts/save'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'customer_phone': phone,
        'contacts': contacts,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to save emergency contacts');
    }
  }
}
