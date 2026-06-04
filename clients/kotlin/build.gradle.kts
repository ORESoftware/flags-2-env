plugins {
    `java-library`
    kotlin("jvm") version "2.0.20"
    `maven-publish`
    signing
}

group = "com.oresoftware"
version = "0.1.0"

dependencies {
    api("com.oresoftware:flags2env:0.1.0")
}

kotlin {
    jvmToolchain(11)
}

java {
    withSourcesJar()
    withJavadocJar()
}

publishing {
    repositories {
        maven {
            name = "sonatype"
            val releasesRepo = uri(System.getenv("SONATYPE_RELEASE_URL") ?: "https://s01.oss.sonatype.org/service/local/staging/deploy/maven2/")
            val snapshotsRepo = uri(System.getenv("SONATYPE_SNAPSHOT_URL") ?: "https://s01.oss.sonatype.org/content/repositories/snapshots/")
            url = if (version.toString().endsWith("SNAPSHOT")) snapshotsRepo else releasesRepo
            credentials {
                username = System.getenv("SONATYPE_USERNAME") ?: ""
                password = System.getenv("SONATYPE_PASSWORD") ?: ""
            }
        }
    }
    publications {
        create<MavenPublication>("mavenJava") {
            from(components["java"])
            artifactId = "flags2env-kotlin"
            pom {
                name.set("flags2env Kotlin")
                description.set("Kotlin facade for the flags2env Java native bridge.")
                url.set("https://github.com/ORESoftware/flags-2-env")
                licenses { license { name.set("MIT"); url.set("https://opensource.org/license/mit") } }
                developers { developer { id.set("oresoftware"); name.set("ORESoftware") } }
                scm { url.set("https://github.com/ORESoftware/flags-2-env") }
            }
        }
    }
}

signing {
    setRequired { project.hasProperty("release") }
    sign(publishing.publications)
}
