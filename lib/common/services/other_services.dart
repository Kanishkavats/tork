class ApiService {
  Future<dynamic> getRequest(String endpoint) async {
    return {'status': 'success', 'data': []};
  }

  Future<dynamic> postRequest(String endpoint, Map<String, dynamic> body) async {
    return {'status': 'success', 'message': 'Operation successful'};
  }
}

class MapService {
  Future<List<Map<String, double>>> getRoutePoints(String from, String to) async {
    return [
      {'latitude': 37.7749, 'longitude': -122.4194},
      {'latitude': 37.7849, 'longitude': -122.4094},
    ];
  }
}

class StorageService {
  final Map<String, String> _data = {};

  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  Future<String?> read(String key) async {
    return _data[key];
  }

  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

class PaymentService {
  Future<bool> processPayment(double amount, String method) async {
    return true;
  }
}

class NotificationService {
  Future<void> showNotification(String title, String body) async {
    // print('Mock Notification: $title - $body');
  }
}
