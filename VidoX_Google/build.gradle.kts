import java.io.File

// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.ksp) apply false
}

// Keep build outputs out of iCloud-synced Documents. Finder/iCloud duplicates
// ("Foo 2.class") under app/build and break dex with "defined multiple times".
val localBuildRoot = File(System.getProperty("user.home"), "Library/Caches/VidoX_Google")
layout.buildDirectory.set(localBuildRoot.resolve("root"))
subprojects {
    layout.buildDirectory.set(localBuildRoot.resolve(name))
}
