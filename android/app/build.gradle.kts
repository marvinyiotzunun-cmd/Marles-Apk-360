plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "gt.marles.marles360"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "gt.marles.marles360"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Firma fija para que cada APK nuevo se instale encima del anterior.
    // La llave (marles360-firma.p12) está en el repositorio pero cifrada: sin
    // su contraseña no sirve. La contraseña vive solo en el secreto MARLES_FIRMA
    // de GitHub. Sin ella (por ejemplo al compilar en otra computadora) el APK
    // sale con la firma de pruebas de Flutter, que no se instala encima del oficial.
    val claveFirma = System.getenv("MARLES_FIRMA").orEmpty()
    signingConfigs {
        if (claveFirma.isNotEmpty()) {
            create("marles") {
                storeFile = file("marles360-firma.p12")
                storeType = "PKCS12"
                storePassword = claveFirma
                keyAlias = "marles360"
                keyPassword = claveFirma
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (claveFirma.isNotEmpty()) "marles" else "debug")
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
