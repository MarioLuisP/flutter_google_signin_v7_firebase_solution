import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _isGoogleInitialized = false;

  // ── Initialization ──────────────────────────────────────────────────

  Future<void> initializeGoogleSignIn() async {
    if (_isGoogleInitialized) return;
    await _googleSignIn.initialize(
      // This MUST be the Web Client ID, not the Android/iOS client ID.
      // The Web Client ID produces the idToken that Firebase can validate.
      // Get it from: Firebase Console → Project Settings → Web apps → Client ID
      serverClientId: const String.fromEnvironment(
        'GOOGLE_SERVER_CLIENT_ID',
        defaultValue: 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com',
      ),
    );
    _isGoogleInitialized = true;
  }

  // ── Anonymous (always keep a user — no login wall) ──────────────────

  Future<User?> signInAnonymously() async {
    try {
      final result = await _auth.signInAnonymously();
      return result.user;
    } catch (_) {
      return null;
    }
  }

  // ── Google Sign-In (v7 API — one-shot handshake) ─────────────────────
  //
  // ARCHITECTURE NOTE:
  // This method is called ONCE when the user taps "Sign in with Google".
  // After signInWithCredential() succeeds, google_sign_in is DONE.
  // Firebase Auth takes over and persists the session across restarts.
  // On cold start, authStateChanges emits the saved user — this method
  // is NOT called again. That is the whole solution.

  Future<UserCredential?> signInWithGoogle() async {
    try {
      await initializeGoogleSignIn();

      if (!_googleSignIn.supportsAuthenticate()) return null;

      final googleUser = await _googleSignIn.authenticate(
        scopeHint: ['email'],
      );
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } catch (e) {
      // Plugin throws with "cancel" when the user dismisses the dialog.
      // That is not an error — don't surface it.
      if (e.toString().toLowerCase().contains('cancel')) return null;
      rethrow;
    }
  }

  // ── Apple Sign-In (iOS only, with CSRF nonce) ────────────────────────
  //
  // Requires additional iOS setup — see example/README.md #apple-sign-in.
  // Same architectural principle: Apple is the handshake, Firebase is the house.

  Future<UserCredential?> signInWithApple() async {
    try {
      if (!Platform.isIOS) return null;
      if (!await SignInWithApple.isAvailable()) return null;

      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        // authorizationCode is required for Firebase to validate correctly
        accessToken: appleCredential.authorizationCode,
      );

      final result = await _auth.signInWithCredential(oauthCredential);

      // Apple only sends displayName on the VERY FIRST sign-in.
      // If it's there, save it — it will never come again.
      if (result.user?.displayName == null &&
          appleCredential.givenName != null) {
        await result.user?.updateDisplayName(
          '${appleCredential.givenName} ${appleCredential.familyName ?? ''}'
              .trim(),
        );
      }

      return result;
    } catch (e) {
      if (e.toString().toLowerCase().contains('cancel')) return null;
      rethrow;
    }
  }

  // ── Sign Out → back to anonymous ────────────────────────────────────

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
      await signInAnonymously();
    } catch (_) {
      // Silent — do not interrupt UX
    }
  }

  // ── Delete Account (re-auth required by Firebase) ───────────────────

  Future<bool> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.isAnonymous) return false;

      final reAuthOk = await _reauthenticateUser(user);
      if (!reAuthOk) return false;

      await user.delete();
      await signInAnonymously();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _reauthenticateUser(User user) async {
    try {
      final providerId = user.providerData.first.providerId;

      if (providerId == 'google.com') {
        await initializeGoogleSignIn();
        final googleUser =
            await _googleSignIn.authenticate(scopeHint: ['email']);
        final credential = GoogleAuthProvider.credential(
          idToken: googleUser.authentication.idToken,
        );
        await user.reauthenticateWithCredential(credential);
        return true;
      }

      if (providerId == 'apple.com' && Platform.isIOS) {
        final rawNonce = _generateNonce();
        final nonce = _sha256ofString(rawNonce);
        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: [AppleIDAuthorizationScopes.email],
          nonce: nonce,
        );
        final credential = OAuthProvider('apple.com').credential(
          idToken: appleCredential.identityToken,
          rawNonce: rawNonce,
        );
        await user.reauthenticateWithCredential(credential);
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Stream + getters ─────────────────────────────────────────────────

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  bool get isLoggedIn => currentUser != null && !currentUser!.isAnonymous;
  bool get isAnonymous => currentUser?.isAnonymous ?? true;

  // ── Apple nonce helpers ──────────────────────────────────────────────

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
        length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}
