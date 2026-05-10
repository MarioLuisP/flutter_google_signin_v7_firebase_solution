# Architecture Deep Dive

## The Mental Model Shift

### v6 Mental Model (broken in v7)

```
google_sign_in   ──── maintains Google session ───┐
                                                   ├── both together = "logged in"
firebase_auth    ──── maintains Firebase session ──┘
```

This was the implicit model most developers had with v6. `signInSilently()` re-authenticated the Google side on every cold start. It felt like google_sign_in was managing the session.

### v7 Mental Model (correct)

```
google_sign_in:  ONE-SHOT HANDSHAKE
                 ─────────────────────────────────────────
                 User taps "Sign in with Google"
                 → Google dialog appears (ONCE)
                 → Returns idToken
                 → Done. This SDK is no longer involved.

firebase_auth:   PERMANENT RESIDENCE
                 ─────────────────────────────────────────
                 Receives idToken from handshake
                 → Validates with Firebase servers
                 → Saves session to native secure storage:
                     iOS:     Keychain
                     Android: EncryptedSharedPreferences
                 → On every cold start: reads storage, restores User
                 → Emits User via authStateChanges stream
                 → Renews tokens automatically when they expire (~1h)
                 → Survives: app kill, OS kill, reboot, even uninstall (iOS)
```

The key insight:

> **"Google Sign-In is the key to open the front door.  
> Firebase Auth is the house where you live."**

After the handshake, google_sign_in could be uninstalled and the user would still be logged in. Firebase Auth is the only component that matters for persistence.

---

## Why Nobody Sees This

1. **Google Sign-In docs** describe `signIn()`, `signInSilently()` (v6), `currentUser`, `authenticate()` (v7) in detail. The implicit narrative: this SDK manages the session.

2. **Firebase Auth docs** say "authentication state is persisted on device" — but don't emphasize that this applies to OAuth providers like Google. Most developers assume Firebase Auth persistence = email/password only.

3. **The v7 changelog** lists breaking API changes but does NOT highlight "silent re-auth is gone". Developers discover this in production when users start logging out.

4. **The "fix" attempts** all seem reasonable at first: `attemptLightweightAuthentication()`, SharedPreferences caching, Firestore sync. All are unnecessary work that obscures that Firebase Auth was already solving the problem.

---

## The Three Rules

### Rule 1: Firebase.initializeApp() before runApp()

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: ...);  // ← ALWAYS here
  runApp(const MyApp());
}
```

If you move this to `initState` or a later widget, `AuthProvider`'s constructor runs before Firebase is ready. The `authStateChanges` stream gets wired up incorrectly and never emits the persisted user on cold start.

This was verified by a production rollback: a commit moved `Firebase.initializeApp()` to a lazy-init in a widget, which broke cold start persistence. It was reverted 30 minutes later.

### Rule 2: Wire up authStateChanges in the AuthProvider constructor

```dart
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    // This runs before the first frame is built.
    // The first event emitted will be the persisted user from Firebase.
    _authService.authStateChanges.listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }
}
```

If you wire this up later (e.g., in `initState`), you miss the first emission. The user appears as null until the next Firebase event, causing a login screen flash.

### Rule 3: Call initializeAuth() in addPostFrameCallback

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    context.read<AuthProvider>().initializeAuth();
  });
}
```

This needs `BuildContext` and runs after the widget tree is built. It checks if Firebase already has a user. If not (first install, or token was revoked), creates an anonymous session as fallback.

---

## Data Flow on Cold Start

```
App killed by OS
     │
     ▼
main() runs
     │
     ├── Firebase.initializeApp()
     │        └── Reads saved tokens from native storage
     │
     ├── runApp(MyApp)
     │        └── ChangeNotifierProvider(create: (_) => AuthProvider())
     │                   └── AuthProvider() constructor runs
     │                             └── authStateChanges.listen(...)
     │
     ├── First frame builds
     │
     ├── addPostFrameCallback fires
     │        └── initializeAuth()
     │                   └── existingUser = _auth.currentUser  ← ALREADY SET
     │                             └── (it's the Google user from last session)
     │
     ▼
authStateChanges emits User (from Firebase internal storage)
     │
     ▼
_user = user; notifyListeners();
     │
     ▼
UI shows HomeScreen with user data
     │
Time: 50–200ms from cold start, zero network calls, zero Google dialogs.
```

---

## What Each Component Is Responsible For

| Component | Responsibility | NOT responsible for |
|-----------|---------------|---------------------|
| `google_sign_in` | Initial OAuth handshake | Session persistence |
| `firebase_auth` | Session storage, token refresh, stream | Initial OAuth |
| `AuthService` | Glue: handshake → Firebase credential | UI state |
| `AuthProvider` | UI state, loading, stream listener | Auth logic |

---

## Token Lifecycle

Google OAuth tokens last ~1 hour. When they expire:

1. Firebase Auth detects the expiry on next API call.
2. Firebase sends the **refresh token** to Firebase servers.
3. Firebase servers issue a new access token and idToken.
4. `authStateChanges` may emit a new `User` with the updated token.
5. Your app sees nothing — it just keeps working.

The refresh token itself lasts until:
- User changes their Google password.
- User revokes the app's access in Google Account settings.
- User deletes their Firebase account.

In those cases, `currentUser` becomes `null`, `authStateChanges` emits `null`, and `initializeAuth()` falls back to `signInAnonymously()`.

---

## Anonymous Fallback Pattern

The demo implements "always have a user":

```dart
Future<void> initializeAuth() async {
  final existingUser = _auth.currentUser;
  if (existingUser == null) {
    await signInAnonymously();  // fallback — no Google needed
  }
  // If existingUser != null: either real or anonymous already exists.
  // Either way: there's always a user.
}
```

Benefits:
- No "login wall" — users can try the app before committing.
- Consistent UID from first launch.
- When user later signs in with Google, Firebase links the anonymous user to the Google account automatically (if you use `linkWithCredential` instead of `signInWithCredential`).
