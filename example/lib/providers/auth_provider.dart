import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  User? _user;
  bool _isLoading = false;
  String? _lastError;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _authService.isLoggedIn;
  bool get isAnonymous => _authService.isAnonymous;
  String? get lastError => _lastError;

  String get userName {
    if (!isLoggedIn) return 'Anonymous';
    return _user?.displayName ?? _user?.email?.split('@')[0] ?? 'User';
  }

  String get userEmail => isLoggedIn ? (_user?.email ?? '') : '';
  String get userPhotoUrl => _user?.photoURL ?? '';

  String get userInitials {
    if (!isLoggedIn) return '?';
    final name = _user?.displayName;
    if (name != null && name.isNotEmpty) {
      final parts = name.trim().split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return parts[0][0].toUpperCase();
    }
    final email = _user?.email;
    if (email != null && email.isNotEmpty) return email[0].toUpperCase();
    return '?';
  }

  Color getAvatarColor() {
    if (!isLoggedIn) return Colors.grey.withAlpha(179);
    final email = _user?.email ?? '';
    if (email.isEmpty) return Colors.blue;
    const colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
    ];
    return colors[email.hashCode.abs() % colors.length];
  }

  AuthProvider() {
    _initializeAuthListener();
  }

  // KEY TO PERSISTENCE:
  // This listener connects in the constructor — before the UI is built.
  // On cold start, Firebase Auth emits the restored User (from
  // Keychain on iOS, EncryptedSharedPreferences on Android) as the
  // first event on this stream, before any Google Sign-In is called.
  void _initializeAuthListener() {
    _authService.authStateChanges.listen((User? user) {
      _user = user;
      notifyListeners();
    });
    _user = _authService.currentUser;
  }

  // Called from main.dart in addPostFrameCallback.
  // If Firebase already has a persisted user (real or anonymous), does nothing.
  // If no user exists, creates an anonymous session as a fallback.
  Future<void> initializeAuth() async {
    _isLoading = true;
    notifyListeners();
    try {
      final existingUser = _authService.currentUser;
      if (existingUser == null) {
        await _authService.signInAnonymously();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final result = await _authService.signInWithGoogle();
      return result != null;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithApple() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final result = await _authService.signInWithApple();
      return result != null;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.signOut();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteAccount() async {
    _isLoading = true;
    notifyListeners();
    try {
      return await _authService.deleteAccount();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
