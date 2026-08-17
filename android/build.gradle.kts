allprojects {
    repositories {
        google()
        mavenCentral()
        // Appodeal SDK + its network adapters. stack_appodeal_flutter's own
        // build.gradle already injects this into rootProject.allprojects, so
        // a minimal integration builds without it — it is declared here as
        // well so the app's own adapter dependencies in app/build.gradle.kts
        // don't silently depend on a plugin's side effect.
        maven { url = uri("https://artifactory.appodeal.com/appodeal") }
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
