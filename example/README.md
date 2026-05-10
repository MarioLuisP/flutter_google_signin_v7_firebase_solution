# Demo App — Setup Guide

This is a minimal Flutter app that demonstrates the Google Sign-In v7 + Firebase Auth persistence solution described in the [main README](../README.md).

## What it demonstrates

1. **Sign in once** with Google → Firebase Auth saves the session.
2. **Kill the app** (swipe up / force stop).
3. **Reopen** → you are still signed in, with no Google dialog.

The "Persistence Proof" card in the home screen shows `user.metadata.lastSignInTime` — the timestamp of the actual Google handshake. It doesn't change on restart, proving that Firebase Auth (not Google Sign-In) is restoring the session.

---

## Prerequisites

- Flutter 3.x
- A Firebase project with Google Sign-In enabled
- Android: SHA-1 and SHA-256 fingerprints registered in Firebase Console

---

## Setup (5 minutes)

### Step 1: Firebase project

1. Go to [Firebase Console](https://console.firebase.google.com/) → create a project.
2. Enable **Google Sign-In** under Authentication → Sign-in method.
3. Register your Android app:
   - Package name: `com.example.googleSigninV7Demo`
   - Add SHA-1 and SHA-256 (see Step 3).
4. Register your iOS app (optional):
   - Bundle ID: `com.example.googleSigninV7Demo`

### Step 2: Config files

**Android:**
```bash
# Download google-services.json from Firebase Console
# Place it at: example/android/app/google-services.json
```

**iOS (optional):**
```bash
# Download GoogleService-Info.plist from Firebase Console
# Place it at: example/ios/Runner/GoogleService-Info.plist
```

**Flutter — firebase_options.dart:**
```bash
# Option A: FlutterFire CLI (recommended)
dart pub global activate flutterfire_cli
cd example
flutterfire configure

# Option B: Manual
cp lib/firebase_options.dart.template lib/firebase_options.dart
# Edit lib/firebase_options.dart — replace ALL_CAPS placeholders
```

### Step 3: Android SHA fingerprints

Google Sign-In on Android requires SHA fingerprints in Firebase Console.
Without them, sign-in fails with `ApiException 10` (no clear error message).

```bash
cd example/android
./gradlew signingReport
```

Copy **SHA-1 and SHA-256** from the debug entry to:
Firebase Console → Project Settings → Your Android app → Add fingerprint.

Then download a **fresh** `google-services.json` (the old one doesn't have the fingerprints yet).

### Step 4: Web Client ID

In `lib/services/auth_service.dart`, `serverClientId` reads from `--dart-define`:

```dart
serverClientId: const String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com',
),
```

Get your **Web Client ID** from Firebase Console → Project Settings → General → Web apps → Client ID.
It is also in `google-services.json` under `oauth_client` with `"client_type": 3`.

Run with:
```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=123456-xxxx.apps.googleusercontent.com
```

Or replace the `defaultValue` in the code for quick testing (do not commit real IDs).

### Step 5: Run

```bash
cd example
flutter pub get
flutter run
```

---

## iOS — Additional Setup

### Info.plist

Add to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
<key>GIDClientID</key>
<string>YOUR_IOS_CLIENT_ID.apps.googleusercontent.com</string>
<key>GIDServerClientID</key>
<string>YOUR_WEB_CLIENT_ID.apps.googleusercontent.com</string>
```

`REVERSED_CLIENT_ID` is the iOS Client ID reversed:
`com.googleusercontent.apps.NUMERIC_ID-SUFFIX`

`GIDServerClientID` must be the **Web Client ID**, not the iOS one. Using the wrong one causes `INVALID_IDP_RESPONSE`.

### Apple Sign-In

The "Sign in with Apple" button appears automatically on iOS (`Platform.isIOS` check in `main.dart`).
It requires `Runner.entitlements` with the `com.apple.developer.applesignin` capability and an Apple Developer account. See [ARCHITECTURE.md](../docs/ARCHITECTURE.md).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ApiException 10` | SHA fingerprints not in Firebase | Add SHA-1 + SHA-256, re-download `google-services.json` |
| `INVALID_IDP_RESPONSE` | `serverClientId` is the Android/iOS ID | Use the Web Client ID (`client_type: 3`) |
| Google dialog on every restart | `Firebase.initializeApp()` after `runApp()` | Move it to `main()` before `runApp()` |
| Google dialog on every restart | `authStateChanges` not listened | Wire listener in `AuthProvider()` constructor |
| `AuthorizationErrorCode.unknown` (Apple) | Missing entitlement | Add `com.apple.developer.applesignin` to `Runner.entitlements` |
| `MissingPluginException` | Stale build | `flutter clean && flutter pub get && flutter run` |
