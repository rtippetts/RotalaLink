# Codemagic Setup (AquaSpec)

## 1) Add project config
- Commit and push `codemagic.yaml` at repo root.
- In Codemagic, connect this repo.
- In the app settings, choose workflow:
  - `android_release`
  - `ios_release`

## 2) Android secrets (required)
Create these environment variables in Codemagic:
- `CM_ANDROID_KEYSTORE_BASE64`
- `CM_ANDROID_KEYSTORE_PASSWORD`
- `CM_ANDROID_KEY_ALIAS`
- `CM_ANDROID_KEY_PASSWORD`

How to create `CM_ANDROID_KEYSTORE_BASE64` from your existing keystore:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
```

Paste clipboard contents into `CM_ANDROID_KEYSTORE_BASE64`.

## 3) iOS signing/TestFlight secrets (required for iOS workflow)
Create these environment variables in Codemagic:
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_IDENTIFIER`
- `APP_STORE_CONNECT_PRIVATE_KEY`

Notes:
- `APP_STORE_CONNECT_PRIVATE_KEY` is the full contents of your `.p8` key.
- Make sure bundle id exists in App Store Connect:
  - `com.rotalasystems.rotalalink`

## 4) Trigger builds
- Run `android_release` workflow to produce:
  - `build/app/outputs/bundle/release/app-release.aab`
- Run `ios_release` workflow to produce:
  - `build/ios/ipa/*.ipa`

## 5) Optional publishing automation
- Current workflows build artifacts only.
- If you want, we can add:
  - auto-upload AAB to Google Play internal track
  - auto-upload IPA to TestFlight
