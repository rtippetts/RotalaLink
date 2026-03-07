# AquaSpec Release Checklist

## 1) Versioning
- Update `pubspec.yaml` version before each store submission.
- Example: `version: 1.0.1+5`

## 2) Android (Google Play)
- Ensure `android/app/build.gradle.kts` release signing is configured.
- Create `android/key.properties` from `android/key.properties.example`.
- Put your upload keystore file at the path used by `storeFile`.
- Build:
  - `flutter clean`
  - `flutter pub get`
  - `flutter build appbundle --release`
- Upload `build/app/outputs/bundle/release/app-release.aab` to Play Console.

## 3) iOS (App Store)
- Confirm bundle id in Xcode matches App Store Connect app:
  - Current: `com.rotalasystems.rotalalink`
- On a Mac:
  - `flutter clean`
  - `flutter pub get`
  - `flutter build ipa --release`
- Upload the generated `.ipa` via Xcode Organizer or Transporter.

## 4) Store Readiness
- Test release build on physical Android and iPhone devices.
- Verify permissions prompts:
  - Camera
  - Photo library
  - Bluetooth
- Verify deep link flow (`rotala://auth-reset`).
- Prepare required store metadata:
  - Privacy policy URL
  - Support URL
  - App screenshots
  - Data safety / privacy answers

## 5) Final Checks
- Run:
  - `flutter analyze`
  - `flutter test`
- Confirm login, tank creation limits, and measurement limits work in release mode.
