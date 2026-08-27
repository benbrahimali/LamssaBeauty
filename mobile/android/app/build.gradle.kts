import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Lit android/app/google-services.json et génère les ressources Firebase.
    id("com.google.gms.google-services")
}

// Signature de release (§7.1). Les identifiants du keystore vivent dans
// android/key.properties, jamais dans le dépôt : quiconque possède ce fichier
// et le .jks peut publier une mise à jour au nom de LAMSSA.
val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreFile.inputStream().use { keystoreProperties.load(it) }
}

// Clé Google Maps. Elle finit dans l'APK — c'est inévitable — mais elle n'a
// pas à être dans le dépôt : publiée sur GitHub, elle est à portée de n'importe
// quel script, et la facturation est pour le propriétaire du projet.
// À restreindre par package + empreinte SHA-1 dans la console Google Cloud.
val localProperties = Properties()
val localFile = rootProject.file("local.properties")
if (localFile.exists()) {
    localFile.inputStream().use { localProperties.load(it) }
}
val mapsApiKey: String = localProperties.getProperty("MAPS_API_KEY") ?: ""


android {
    namespace = "tn.lamssa.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Exigé par flutter_local_notifications 17+ (API de dates Java 8).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Doit rester identique au package_name de google-services.json,
        // sinon FCM n'atteindra jamais l'appareil — et sans erreur explicite.
        applicationId = "tn.lamssa.app"
        // Sans clé locale, la carte reste grise : le reste de l'app tourne.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Le fichier peut manquer (poste neuf, CI sans secrets) : on ne fait
            // pas échouer la configuration Gradle pour autant, le build de
            // release retombera sur la clé de debug avec un avertissement.
            val path = keystoreProperties.getProperty("storeFile")
            if (path != null) {
                storeFile = rootProject.file(path)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.getProperty("storeFile") != null) {
                signingConfigs.getByName("release")
            } else {
                // Un APK signé en debug est refusé par le Play Store : ce repli
                // ne sert qu'à garder `flutter run --release` utilisable.
                logger.warn(
                    "LAMSSA: android/key.properties absent — build de release " +
                        "signé avec la clé de debug, non publiable."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
