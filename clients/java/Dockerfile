FROM eclipse-temurin:21-jdk

WORKDIR /repo
COPY . .

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN make clean && make all
RUN cc -std=c99 -fPIC -shared -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" clients/java/native/flags2env_jni.c src/parser.c -o build/libflags2env_jni.so
RUN javac -d /tmp/java clients/java/src/main/java/com/oresoftware/flags2env/Flags2Env.java clients/java/src/test/java/com/oresoftware/flags2env/Flags2EnvTest.java

CMD cd tests/fixtures/nested/deeper && java -Djava.library.path=/repo/build -cp /tmp/java com.oresoftware.flags2env.Flags2EnvTest
