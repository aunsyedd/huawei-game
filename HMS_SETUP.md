# Huawei Mobile Services — what is done and what is left

## Done
- Every HMS feature is behind an interface in `lib/services/hms/`:
  - `AccountService` → **`HmsAccountService` (real HUAWEI ID sign-in, Account Kit)** when HMS Core is
    installed, `FakeAccountService` (local guest profile) otherwise
  - `GameService` (3 leaderboards, 8 achievements) → `FakeGameService` (stored in shared_preferences)
  - `PushService` → `FakePushService` (shows the configured haze alert as an in-app banner)
  - `AirQualityService` → `ConfigAirQualityService` (reads `assets/data/air_quality_alerts.json`)
- `HmsDetector` asks Android over the `haze_royale/hms` MethodChannel whether HMS Core
  (`com.huawei.hwid`) is installed. `MainActivity.kt` answers it, and the manifest has a
  `<queries>` entry so the check works on Android 11+.
- `HmsServices.create()` (in `hms_services.dart`) is the single place that picks real or fake services.
  The menu shows "Offline mode (no HMS)" or "Huawei Mobile Services".

### Account Kit (HUAWEI ID)
- Android SDK `com.huawei.hms:hwid` (Huawei maven repo in `android/build.gradle.kts`), called from
  `MainActivity.kt` over the `haze_royale/account` channel: `silentSignIn`, `signIn`, `signOut`.
  The official Flutter plugin is not used: it lags behind current AGP/Kotlin versions.
- Huawei's AGC Gradle plugin is not used either. `android/app/build.gradle.kts` reads the app id from
  `android/app/agconnect-services.json` into the manifest (`com.huawei.hms.client.appid`) and ships the
  file as an asset. Without the file the app still builds; sign-in reports an error code instead.
- `main.dart` restores an earlier sign-in silently at start-up; the menu button reads
  "Sign in with HUAWEI ID" on HMS devices. A cancelled sign-in keeps the player a guest; other failures
  show a snackbar with the HMS status code. `proguard-rules.pro` keeps the HMS classes in release builds.
- `test/account_service_test.dart` covers the Dart side against a mocked channel.

## Turning HUAWEI ID sign-in on (AppGallery Connect)
1. In AppGallery Connect create a project and an Android app with package
   `com.umpsa.hazeroyale.haze_royale`.
2. Project settings → General information → add the **SHA-256 certificate fingerprint** of the upload key
   (`keytool -list -v -keystore android/app/upload-keystore.jks -alias upload`). Debug builds are
   signed with a different key; add its fingerprint too if you test with `flutter run`.
3. Manage APIs → make sure **Account Kit** is enabled.
4. Download `agconnect-services.json` to `android/app/agconnect-services.json` (gitignored) and rebuild.
5. Test on a phone with HMS Core (any Huawei phone, or install HMS Core on another Android phone).
   Common codes: 6003 = fingerprint not registered / wrong key, 907135000 / 907135702 = app id or
   config missing, 2012 = the player closed the sign-in screen.

## Still left
- `HmsGameService` (leaderboards + achievements) and `HmsPushService`: same pattern, call the Android
  SDKs from `MainActivity.kt`, then return them from `HmsServices.create()` when `hmsAvailable` is true.
  Map the leaderboard and achievement ids in `game_service.dart` to the ids created in AppGallery Connect.

## Air quality data
Haze alerts currently come from `assets/data/air_quality_alerts.json` (the config fallback).
A live Malaysian air-quality feed has not been checked yet. Look on data.gov.my / api.data.gov.my for an
Air Pollutant Index dataset; if a usable one exists, implement `AirQualityService` against it and send
Push Kit messages when the API goes above 100.
