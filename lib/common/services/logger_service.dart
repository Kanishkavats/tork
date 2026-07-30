import 'package:flutter/foundation.dart';

/// Simple static logger service used throughout the app.
/// Uses Flutter's [debugPrint] so logs are suppressed in release builds.
class LoggerService {
  /// Debug log
  static void d(String message) {
    debugPrint('[DEBUG] $message');
  }

  /// Info log
  static void i(String message) {
    debugPrint('[INFO] $message');
  }

  /// Warning log
  static void w(String message) {
    debugPrint('[WARN] $message');
  }

  /// Error log
  static void e(String message) {
    debugPrint('[ERROR] $message');
  }
}
