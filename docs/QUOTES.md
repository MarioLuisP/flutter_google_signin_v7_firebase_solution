# Official Statements — Google Flutter Team

Verbatim quotes from the official Google Flutter team on the google_sign_in v7 breaking change.
All quotes are from the public GitHub issue tracker, linked below.

---

## Stuart Morgan — Flutter team maintainer of `google_sign_in`

**[@stuartmorgan-g](https://github.com/stuartmorgan-g)**

### On why silent sign-in was removed (July 12, 2025)

Issue [#172066](https://github.com/flutter/flutter/issues/172066) — *"attemptLightweightAuthentication() always shows account selection"*

> *"`google_sign_in` 7.x does not have a silent login option, specifically because some platforms—including Android—do not provide an option in the currently supported authentication SDKs that will guarantee silent sign in. Closing as out of scope since we can't control this behavior at the plugin level."*

### On why this is not a regression (August 30, 2025)

Issue [#174736](https://github.com/flutter/flutter/issues/174736) — *"google_sign_in does not silently re-auth after app restart"*

> *"Not from the perspective of the plugin. The goal of the plugin is to wrap the recommended Google Sign In SDK; `google_sign_in` 7.x switched from a deprecated, no-longer-supported SDK to the only SDK that is currently supported. That was, and still is, the intended behavior of the update."*

On responsibility:

> *"The fact that you happen to be calling that SDK via a Dart wrapper in the context of a Flutter application is irrelevant to the request; a non-Flutter app would have exactly the same behavior. [...] The Flutter team has no opinion about what Google Sign In experience on Android should be, as that is not our role."*

---

## Firebase / FlutterFire — Official Documentation

**Source:** [firebase.flutter.dev/docs/auth/usage](https://firebase.flutter.dev/docs/auth/usage/)

On persistence:

> *"On native platforms such as Android & iOS, this behavior is not configurable and the user's authentication state will be persisted on-device between app restarts."*

On iOS keychain persistence (bonus — survives even uninstall):

> *"Note: uninstalling your application on iOS or macOS can still preserve your users authentication state between app re-installs as the underlying Firebase iOS SDK persists authentication state to keychain."*

---

## Google Sign-In v7.0.0 Changelog

**Source:** [pub.dev/packages/google_sign_in/changelog](https://pub.dev/packages/google_sign_in/changelog)

> *"BREAKING CHANGE: Many APIs have changed or been replaced to reflect the current APIs and best practices of the underlying platform SDKs. The GoogleSignIn instance is now a singleton. Clients must call and await the new initialize method before calling any other methods. Authentication and authorization are now separate steps."*

Note: The changelog does **not** mention the loss of silent re-authentication as a highlighted change. Developers discover this only when they migrate and see users "logged out" on every cold start.

---

## GitHub Issues — Developers hitting the same wall

| Issue | Title | Date | Status |
|-------|-------|------|--------|
| [#171745](https://github.com/flutter/flutter/issues/171745) | `[google_sign_in]` how to save login google | Jul 8, 2025 | Closed — duplicate of #172066 |
| [#172066](https://github.com/flutter/flutter/issues/172066) | `attemptLightweightAuthentication()` always shows account selection | Jul 12, 2025 | **Closed as NOT PLANNED** |
| [#174736](https://github.com/flutter/flutter/issues/174736) | google_sign_in does not silently re-auth after app restart | Aug 29, 2025 | Closed — duplicate of #172066 |

Three independent developers, three separate months, same symptom. All closed without a fix.

---

## Conclusion

The behavior is **intentional**. v7 switched from a deprecated Google SDK (legacy `play-services-auth`) to the only currently supported one (Credential Manager on Android). Credential Manager does not guarantee silent sign-in by design — Google wants the user to see the account selection for security and UX reasons.

**There is no fix planned. There is no workaround on the Google Sign-In side.**

The solution is architectural: use Firebase Auth for persistence (it was doing this all along) and treat Google Sign-In as a one-shot handshake. See [ARCHITECTURE.md](ARCHITECTURE.md).
