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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    project.pluginManager.withPlugin("com.android.library") {
        val android = project.extensions.getByName("android") as com.android.build.gradle.LibraryExtension
        if (android.namespace == null) {
            android.namespace = "com.legacy." + project.name.replace("-", "_")
        }
        android.compileSdk = 34
    }
}
