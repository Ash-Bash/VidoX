import java.io.File

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.ashbash.vidoxproject"
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "com.ashbash.vidoxproject"
        minSdk = 24
        targetSdk = 37
        versionCode = 12
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
        }
    }

    signingConfigs {
        // Optional release signing via env (local or CI).
        val storePath = System.getenv("VIDOX_STORE_FILE")
        if (!storePath.isNullOrBlank()) {
            create("release") {
                storeFile = file(storePath)
                storePassword = System.getenv("VIDOX_STORE_PASSWORD")
                keyAlias = System.getenv("VIDOX_KEY_ALIAS")
                keyPassword = System.getenv("VIDOX_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            optimization {
                enable = false
            }
            // Prefer release keystore when configured; otherwise debug so assembleRelease
            // still yields an installable APK for local/CI smoke builds.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material3.adaptive)
    implementation(libs.androidx.compose.material3.adaptive.layout)
    implementation(libs.androidx.compose.material3.adaptive.navigation)
    implementation(libs.androidx.compose.material3.window.size)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.okhttp)
    implementation(libs.coil.compose)
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui)
    implementation(libs.youtubedl.android.library)
    implementation(libs.youtubedl.android.ffmpeg)
    implementation(libs.kotlinx.coroutines.android)
    debugImplementation(libs.androidx.compose.ui.tooling)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.junit)
}

// iCloud/Finder sometimes creates "BuildConfig 3.java" / "PlatformParity 2.class"
// copies under build dirs, which break resource/Java/dex compilation.
tasks.register("scrubIcloudBuildDuplicates") {
    val appBuildPath = layout.buildDirectory.get().asFile.absolutePath
    val rootBuildPath = rootProject.layout.buildDirectory.get().asFile.absolutePath
    doLast {
        listOf(appBuildPath, rootBuildPath).forEach { path ->
            val root = File(path)
            if (!root.exists()) return@forEach
            root.walkTopDown()
                .filter { it.isFile && it.name.contains(' ') }
                .forEach { it.delete() }
        }
    }
}

tasks.named("preBuild").configure {
    dependsOn("scrubIcloudBuildDuplicates")
}

// Also scrub right before dex — iCloud can duplicate .class files after compile.
listOf(
    "dexBuilderDebug",
    "dexBuilderRelease",
    "compileDebugKotlin",
    "compileReleaseKotlin"
).forEach { taskName ->
    tasks.matching { it.name == taskName }.configureEach {
        dependsOn("scrubIcloudBuildDuplicates")
    }
}
