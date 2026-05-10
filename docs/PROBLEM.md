# The Problem: google_sign_in v7 and Session Persistence

## What Breaks

In **google_sign_in v6** (legacy):
- `signInSilently()` re-authenticated in the background on cold start.
- `_googleSignIn.currentUser` was populated after restart.
- The session felt like it persisted through the Google Sign-In plugin.

In **google_sign_in v7** (2025):
- `signInSilently()` was **removed**.
- `attemptLightweightAuthentication()` exists but **always shows UI** — it is not silent.
- `_googleSignIn.currentUser` is **always null** on cold start.
- Result: every time Android kills the app (memory cleanup), the user appears "logged out".

## User Impact

```
Day 1:  User signs in with Google         ✅
Day 2:  User opens app normally           ✅
Day 5:  Android kills app (background)    💀
Day 5:  User opens app again              ❌ Login screen. Must re-authenticate.
```

This happens every time the OS reclaims memory — which is standard behavior, not a bug.

## Why the "Obvious" Fixes Don't Work

### Fix attempt 1: `attemptLightweightAuthentication()`

```dart
// This does NOT work as silent auth
await _googleSignIn.attemptLightweightAuthentication();
```

Result: Always shows an account selection UI (a bottom sheet or transition). Not silent. Users see a Google screen even when they didn't tap anything.

Confirmed by maintainer Stuart Morgan in issue [#172066](https://github.com/flutter/flutter/issues/172066):
> *"google_sign_in 7.x does not have a silent login option"*

### Fix attempt 2: Cache the last email in SharedPreferences

```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('last_google_email', user.email!);
```

Result: This stores a display value, not a session token. You can show the email in the UI but the user is not actually authenticated. Any Firebase operation will fail or treat them as anonymous.

Also: completely unnecessary. Firebase Auth already persists the real session — you're duplicating work with a worse version.

### Fix attempt 3: Sync user to Firestore

```dart
await FirebaseFirestore.instance
    .collection('users')
    .doc(user.uid)
    .set({'email': user.email, 'lastSeen': ...});
```

Result: Firestore stores user data, not auth sessions. Firebase Auth already has the session. This is extra work that provides zero auth benefit.

### Fix attempt 4: Manual token caching

Storing access tokens or refresh tokens manually is fragile, complex, and a security risk. Google rotates tokens, revokes them without notice, and any local cache can get stale.

## Root Cause

The root cause is a **mental model mismatch**:

- Developers coming from v6 think google_sign_in maintains the session.
- In reality, **Firebase Auth was always maintaining the session** — on iOS via Keychain, on Android via EncryptedSharedPreferences.
- v6's `signInSilently()` was calling the deprecated `play-services-auth` Google SDK. It appeared to "maintain the session" but was actually re-authenticating silently on every start.
- v7 uses Google's current SDK (Credential Manager on Android), which does not provide silent re-auth by design.

So v7 didn't remove persistence — it revealed that persistence was always Firebase Auth's job.

## Timeline of GitHub Issues

Three developers independently reported this in 2025:

| Date | Issue | Resolution |
|------|-------|------------|
| Jul 8, 2025 | [#171745](https://github.com/flutter/flutter/issues/171745) — "how to save login google" | Closed as duplicate |
| Jul 12, 2025 | [#172066](https://github.com/flutter/flutter/issues/172066) — "attemptLightweightAuthentication() always shows account selection" | **Closed as NOT PLANNED** |
| Aug 29, 2025 | [#174736](https://github.com/flutter/flutter/issues/174736) — "does not silently re-auth after app restart" | Closed as duplicate |

All three closed without a fix. The maintainer's position: this is intended behavior, not a bug.

## What This Means for Migration (v6 → v7)

If you're migrating:

1. Remove all calls to `signInSilently()` — it doesn't exist.
2. Remove all calls to `attemptLightweightAuthentication()` — it shows UI.
3. Remove any SharedPreferences or Firestore caching of Google user data.
4. Keep `Firebase.initializeApp()` in `main()`, before `runApp()`.
5. Wire up `authStateChanges.listen(...)` in your auth provider constructor.

That's it. Firebase Auth was already persisting the session. You just weren't relying on it.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the correct implementation.
