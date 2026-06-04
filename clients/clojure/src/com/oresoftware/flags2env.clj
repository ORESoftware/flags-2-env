(ns com.oresoftware.flags2env
  (:refer-clojure :exclude [apply])
  (:import [com.oresoftware.flags2env Flags2Env]))

(defn parse
  ([argv]
   (into {} (Flags2Env/parse (into-array String (map str argv)))))
  ([config-path argv]
   (into {} (Flags2Env/parse config-path (into-array String (map str argv))))))

(defn parse-process
  ([]
   (into {} (Flags2Env/parseProcess)))
  ([config-path]
   (into {} (Flags2Env/parseProcess config-path))))

(defn apply
  ([env argv]
   (merge env (parse argv)))
  ([env config-path argv]
   (merge env (parse config-path argv))))
