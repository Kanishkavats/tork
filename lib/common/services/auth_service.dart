import 'dart:async';

class AuthService {
  bool _isLoggedIn = false;
  String? _currentUser;

  bool get isLoggedIn => _isLoggedIn;
  String? get currentUser => _currentUser;

  Future<bool> login(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 800)); // Mock network delay
    _isLoggedIn = true;
    _currentUser = email;
    return true;
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _currentUser = null;
  }
}
