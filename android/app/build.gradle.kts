import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val mapsProperties = Properties()
val mapsPropertiesFile = rootProject.file("keys.properties")
if (mapsPropertiesFile.isFile) {
    mapsPropertiesFile.inputStream().use { mapsProperties.load(it) }
}

android {
    namespace = "app.pikd.flutter.demo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.pikd.flutter.demo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // PIKDARKit/ARCore requires API 24. Keep this explicit so a change to
        // Flutter's default cannot make a fresh consumer clone fail at merge.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Google Maps API key for the Explore module. The public demo runner
        // requires this ignored local file before building:
        //   android/keys.properties (see keys.properties.example)
        manifestPlaceholders["MAPS_API_KEY"] =
            mapsProperties.getProperty("MAPS_API_KEY")?.trim().orEmpty()
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
