import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'customer/customer_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  final prefs = await SharedPreferences.getInstance();
  final isPink = prefs.getBool('is_pink_theme') ?? false;
  final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  CustomerApp.isPinkTheme.value = isPink;

  // Force initialRoute to '/' so the onboarding flow (Splash -> OTP -> Profile) runs every time for testing
  runApp(const CustomerApp(initialRoute: '/'));
}
