allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Some plugins compile against an older Android API than their own
// dependencies require (file_picker 8 against 34, while
// flutter_plugin_android_lifecycle needs 36). Compile every Android library
// against the app's compileSdk, which Flutter sets.
subprojects {
    afterEvaluate {
        val appCompileSdk =
            rootProject.project(":app")
                .extensions.getByType<com.android.build.api.dsl.ApplicationExtension>()
                .compileSdk
        extensions.findByType<com.android.build.api.dsl.LibraryExtension>()?.let { library ->
            val own = library.compileSdk
            if (appCompileSdk != null && (own == null || own < appCompileSdk)) {
                library.compileSdk = appCompileSdk
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
