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
subprojects {
    project.evaluationDependsOn(":app")
}

// Plugins such as flutter_secure_storage still declare compileSdk 34/35.
// This SDK only has API 36+, and auto-download crashes on Windows 10.
subprojects {
    fun pinLibraryCompileSdk() {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.compileSdk = 36
    }
    if (state.executed) {
        pinLibraryCompileSdk()
    } else {
        afterEvaluate { pinLibraryCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
