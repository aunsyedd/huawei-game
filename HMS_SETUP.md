# Huawei Mobile Services — what is done and what is left

## Done
- Every HMS feature is behind an interface in `lib/services/hms/` with an offline fake:
  - `AccountService` → `FakeAccountService` (local guest profile)
  - `GameService` (3 leaderboards, 8 achievements) → `FakeGameService` (stored in shared_preferences)
  - `PushService` → `FakePushService` (shows the configured haze alert as an in-app banner)
  - `AirQualityService` → `ConfigAirQualityService` (reads `assets/data/air_quality_alerts.json`)
- `HmsDetector` asks Android over the `haze_royale/hms` MethodChannel whether HMS Core
  (`com.huawei.hwid`) is installed. `MainActivity.kt` answers it, and the manifest has a
  `<queries>` entry so the check works on Android 11+.
- `HmsServices.create()` (in `hms_services.dart`) is the single place that picks real or fake services.
  Today it always returns fakes; the menu shows "Offline mode (no HMS)" or "Huawei Mobile Services".

## Left for after the HMS workshop (Prompt 4)
1. Create the app in AppGallery Connect with package `com.umpsa.hazeroyale.haze_royale`.
   Enable Account Kit, Game Service and Push Kit. Add the SHA-256 fingerprint of your signing key
   (`cd android && ./gradlew signingReport`).
2. Download `agconnect-services.json` and put it at `android/app/agconnect-services.json`.
3. Gradle (Kotlin DSL):
   - `android/settings.gradle.kts`: inside `pluginManagement { repositories { ... } }` add
     `maven { url = uri("https://developer.huawei.com/repo/") }`, and register the AGC plugin:
     `id("com.huawei.agconnect") version "<version from the workshop>" apply false` in `plugins { }`.
   - `android/build.gradle.kts`: add the same Huawei maven repo under `allprojects { repositories { } }`.
   - `android/app/build.gradle.kts`: add `id("com.huawei.agconnect")` to `plugins { }`.
4. Add the official Huawei Flutter plugins (check versions at the workshop):
   `huawei_account`, `huawei_push`, and the Game Service plugin if it is still offered for your region.
   If a kit has no Flutter plugin, call the Android SDK from `MainActivity.kt` over a MethodChannel,
   the same way `isHmsAvailable` works.
5. Write `HmsAccountService`, `HmsGameService` and `HmsPushService` that implement the existing
   interfaces, then return them from `HmsServices.create()` when `hmsAvailable` is true.
   Map the leaderboard and achievement ids in `game_service.dart` to the ids you create in AppGallery Connect.

## Air quality data
Haze alerts currently come from `assets/data/air_quality_alerts.json` (the config fallback).
A live Malaysian air-quality feed has not been checked yet. Look on data.gov.my / api.data.gov.my for an
Air Pollutant Index dataset; if a usable one exists, implement `AirQualityService` against it and send
Push Kit messages when the API goes above 100.
