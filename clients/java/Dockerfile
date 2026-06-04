FROM eclipse-temurin:21-jdk

WORKDIR /repo
COPY Makefile ./
COPY src ./src
COPY tests ./tests
COPY clients/java ./clients/java

RUN apt-get update && apt-get install -y --no-install-recommends build-essential make && rm -rf /var/lib/apt/lists/*
RUN mkdir -p tests/fixtures/nested/deeper && make clean && make all
RUN cc -std=c99 -fPIC -shared -I"$JAVA_HOME/include" -I"$JAVA_HOME/include/linux" clients/java/native/flags2env_jni.c src/parser.c -o build/libflags2env_jni.so
RUN javac -d /tmp/java clients/java/src/main/java/com/oresoftware/flags2env/Flags2Env.java clients/java/src/test/java/com/oresoftware/flags2env/Flags2EnvTest.java
RUN useradd --create-home --shell /bin/sh flags2env && \
  mkdir -p /tmp/flags2env-cache && \
  chown -R flags2env:flags2env /repo /tmp/java /tmp/flags2env-cache

ENV HOME=/home/flags2env
ENV XDG_CACHE_HOME=/tmp/flags2env-cache
USER flags2env

CMD cd tests/fixtures/nested/deeper && java -Djava.library.path=/repo/build -cp /tmp/java com.oresoftware.flags2env.Flags2EnvTest
