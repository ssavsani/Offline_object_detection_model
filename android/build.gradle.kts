allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// The onnxruntime plugin's own Android module hardcodes compileSdkVersion 33,
// which is now lower than what several of its transitive androidx
// dependencies (core-ktx, lifecycle, exifinterface, ...) require. Force every
// plugin subproject to compile against a modern SDK so the AAR metadata check
// passes without having to fork the plugin.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.withGroovyBuilder {
            setProperty("compileSdk", 36)
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
