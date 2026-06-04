(ns build
  (:require [clojure.tools.build.api :as b]))

(def lib 'com.oresoftware/flags2env-clojure)
(def version "0.1.0")
(def class-dir "target/classes")
(def jar-file (format "target/%s-%s.jar" (name lib) version))
(def sources-jar-file (format "target/%s-%s-sources.jar" (name lib) version))
(def basis (b/create-basis {:project "deps.edn"}))
(def sonatype-url
  (or (System/getenv "SONATYPE_RELEASE_URL")
      (System/getenv "CENTRAL_OSSRH_DEPLOY_URL")
      "https://ossrh-staging-api.central.sonatype.com/service/local/staging/deploy/maven2/"))
(def sonatype-repository-id
  (or (System/getenv "SONATYPE_REPOSITORY_ID")
      "ossrh"))

(defn clean [_]
  (b/delete {:path "target"}))

(defn jar [_]
  (clean nil)
  (b/copy-dir {:src-dirs ["src"] :target-dir class-dir})
  (b/write-pom
    {:class-dir class-dir
     :lib lib
     :version version
     :basis basis
     :src-dirs ["src"]
     :pom-data
     [[:name "flags2env Clojure"]
      [:description "Clojure facade for the flags2env Java native bridge."]
      [:url "https://github.com/ORESoftware/flags-2-env"]
      [:licenses
       [:license
        [:name "MIT"]
        [:url "https://opensource.org/license/mit"]]]
      [:developers
       [:developer
        [:id "oresoftware"]
        [:name "ORESoftware"]]]
      [:scm
       [:url "https://github.com/ORESoftware/flags-2-env"]
       [:connection "scm:git:https://github.com/ORESoftware/flags-2-env.git"]]]})
  (b/jar {:class-dir class-dir :jar-file jar-file}))

(defn source-jar [_]
  (b/jar {:class-dir "src" :jar-file sources-jar-file}))

(defn deploy [_]
  (jar nil)
  (source-jar nil)
  (b/process
    {:command-args
     ["mvn" "-B" "org.apache.maven.plugins:maven-gpg-plugin:3.2.7:sign-and-deploy-file"
      (str "-Dfile=" jar-file)
      (str "-DpomFile=" class-dir "/META-INF/maven/com.oresoftware/flags2env-clojure/pom.xml")
      (str "-Dsources=" sources-jar-file)
      (str "-DrepositoryId=" sonatype-repository-id)
      (str "-Durl=" sonatype-url)]}))
