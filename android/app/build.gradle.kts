import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload key for AppGallery. android/key.properties and the keystore are
// gitignored; without them release builds fall back to the debug key.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasUploadKey = keystoreProperties.getProperty("storeFile") != null

// HUAWEI AppGallery Connect config (android/app/agconnect-services.json, gitignored).
// Instead of Huawei's Gradle plugin we read the app id for the manifest and ship
// the file as an asset, which is all Account Kit needs. Without it the app still
// builds and plays; HUAWEI ID sign-in just reports that it is not configured.
val agconnectFile = file("agconnect-services.json")
val hmsAppId: String = if (agconnectFile.exists()) {
    val json = groovy.json.JsonSlurper().parse(agconnectFile) as Map<*, *>
    ((json["client"] as? Map<*, *>)?.get("app_id") ?: (json["app_info"] as? Map<*, *>)?.get("app_id"))?.toString() ?: ""
} else {
    ""
}
val agconnectAssets = layout.buildDirectory.dir("generated/agconnect_assets").get().asFile
agconnectAssets.mkdirs()
File(agconnectAssets, "agconnect-services.json").let { out ->
    if (agconnectFile.exists()) agconnectFile.copyTo(out, overwrite = true) else out.delete()
}

android {
    namespace = "com.umpsa.hazeroyale.haze_royale"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.umpsa.hazeroyale.haze_royale"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["hmsAppId"] = hmsAppId
    }

    sourceSets.getByName("main").assets.srcDir(agconnectAssets)

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasUploadKey) "upload" else "debug")
            // Keeps the HMS SDK classes R8 would otherwise strip or rename.
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    // HUAWEI Account Kit: sign in with HUAWEI ID. (6.15.0.300 is listed on Huawei's repo
    // but has no .pom, so Gradle cannot resolve it; 6.12.0.300 is the newest complete one.)
    implementation("com.huawei.hms:hwid:6.12.0.300")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
