plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.asite.rfdetr_object_detection"
    compileSdk = flutter.compileSdkVersion
    // whisper_ggml requires a newer NDK than flutter.ndkVersion currently
    // pins; NDKs are backward compatible, so pin the higher version project
    // wide rather than leave every plugin build on a mismatched default.
    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.asite.rfdetr_object_detection"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // lib_llama_cpp_android (SmolVLM2's llama.cpp mtmd binding) declares
        // minSdk 28 in its own manifest; Flutter's template default (24) fails
        // the manifest merge, so this project must match it.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // llama.cpp-based native backend loaders (ggml_backend_load_all_from_path,
    // used by lib_llama_cpp for SmolVLM2) need their .so files (e.g.
    // libggml-cpu-*.so) present as real files on disk to scan; with the
    // modern default (native libs kept compressed inside the APK, loaded
    // straight from the zip), they can't find a real directory to scan and
    // model loading fails with "no backends are loaded". AGP rejects setting
    // android:extractNativeLibs directly in the manifest for this AGP
    // version -- it must be set here instead.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
