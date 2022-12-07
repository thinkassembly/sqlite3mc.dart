import java.util.Properties

plugins {
    id("com.android.library") version ("7.2.1")
    id("maven-publish")
    id("signing")
}

val sqliteMinor = 39
val sqlitePatch = 2

group = "eu.simonbinder"
version = "3.$sqliteMinor.$sqlitePatch"
description = "Native sqlite3 library without JNI bindings"

repositories {
    mavenCentral()
    google()
}

android {
    compileSdk = 32
    buildToolsVersion = "32.0.0"
    ndkVersion = "24.0.8215888"

    defaultConfig {
        minSdk = 16

        ndk {
            //    abiFilters += setOf("armeabi-v7a", "arm64-v8a" , "x86", "x86_64")
            abiFilters += setOf("x86", "armeabi-v7a", "arm64-v8a")

        }

        externalNativeBuild {
            // For ndk-build, instead use the ndkBuild block.
            cmake {
                // Passes optional arguments to CMake.
                arguments += listOf("-DANDROID_ARM_NEON=ON")

            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    externalNativeBuild {
        cmake {
            path = file("cpp/CMakeLists.txt")
            version = "3.22.1"


        }
    }

    libraryVariants.forEach {
        it.generateBuildConfigProvider.configure { enabled = false }
    }
}

val androidSourcesJar by tasks.registering(Jar::class) {
    archiveClassifier.set("sources")
    from(android.sourceSets.getByName("main").java.srcDirs)
}

val secretsFile = rootProject.file("local.properties")
val secretProperties = Properties()

if (secretsFile.exists()) {
    secretsFile.reader().use { secretProperties.load(it) }

    secretProperties.forEach { key, value ->
        if (key is String && key.startsWith("signing")) {
            ext[key] = value
        }
    }
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            groupId = project.group.toString()
            artifactId = project.name
            version = project.version.toString()

            artifact("$buildDir/outputs/aar/${project.name}-release.aar")
            artifact(androidSourcesJar)

            pom {
                name.set(project.name)
                description.set(project.description)
                url.set("https://github.com/simolus3/sqlite-native-libraries")

                developers {
                    developer {
                        id.set("simonbinder")
                        name.set("Simon Binder")
                        email.set("oss@simonbinder.eu")
                    }
                }

                licenses {
                    license {
                        name.set("Public Domain")
                        url.set("https://www.sqlite.org/copyright.html")
                    }
                }

                scm {
                    connection.set("scm:git:github.com/simolus3/sqlite-native-libraries.git")
                    developerConnection.set("scm:git:ssh://github.com/simolus3/sqlite-native-libraries.git")
                    url.set("https://github.com/simolus3/sqlite-native-libraries/tree/master")
                }
            }
        }
        create<MavenPublication>("local") {
            groupId = project.group.toString()
            artifactId = project.name
            version = project.version.toString()

            artifact("$buildDir/outputs/aar/${project.name}-release.aar")
            artifact(androidSourcesJar)

            pom {
                name.set(project.name)
                description.set(project.description)
                url.set("https://github.com/simolus3/sqlite-native-libraries")

                developers {
                    developer {
                        id.set("simonbinder")
                        name.set("Simon Binder")
                        email.set("oss@simonbinder.eu")
                    }
                }

                licenses {
                    license {
                        name.set("Public Domain")
                        url.set("https://www.sqlite.org/copyright.html")
                    }
                }

                scm {
                    connection.set("scm:git:github.com/simolus3/sqlite-native-libraries.git")
                    developerConnection.set("scm:git:ssh://github.com/simolus3/sqlite-native-libraries.git")
                    url.set("https://github.com/simolus3/sqlite-native-libraries/tree/master")
                }
            }
        }
    }

    repositories {
        maven {
            name = "sonatype"
            url = uri("https://oss.sonatype.org/service/local/staging/deploy/maven2/")
            credentials {
                username = secretProperties.getProperty("ossrhUsername")
                password = secretProperties.getProperty("ossrhPassword")
            }
        }

        maven {
            name = "here"
            url = uri("build/here/")
        }
    }
}



tasks.named("publish").configure {
    dependsOn("assembleRelease", androidSourcesJar)
}

tasks.withType<PublishToMavenRepository>().configureEach {
    onlyIf {
        (repository == publishing.repositories["sonatype"] &&
                publication == publishing.publications["maven"])
    }
    signing {
        useGpgCmd()
        sign(publishing.publications)
    }
}

tasks.withType<PublishToMavenLocal>().configureEach {
    onlyIf {
        (publication == publishing.publications["local"])
    }

    dependsOn("assembleRelease", androidSourcesJar)


}

