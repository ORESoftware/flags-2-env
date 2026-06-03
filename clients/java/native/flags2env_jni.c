#include "../../../src/parser.h"

#include <jni.h>
#include <stdlib.h>

static jstring f2e_java_string(JNIEnv *env, char *value) {
  if (!value) {
    return (*env)->NewStringUTF(env, "{}");
  }
  jstring out = (*env)->NewStringUTF(env, value);
  f2e_free(value);
  return out;
}

JNIEXPORT jstring JNICALL Java_com_oresoftware_flags2env_Flags2Env_parseProcessJson(JNIEnv *env, jclass cls, jstring config_path) {
  (void)cls;
  const char *config = (*env)->GetStringUTFChars(env, config_path, NULL);
  if (!config) {
    return (*env)->NewStringUTF(env, "{}");
  }

  char *json = f2e_parse_process_from_file(config);
  (*env)->ReleaseStringUTFChars(env, config_path, config);
  return f2e_java_string(env, json);
}

JNIEXPORT jstring JNICALL Java_com_oresoftware_flags2env_Flags2Env_parseProcessDefaultJson(JNIEnv *env, jclass cls) {
  (void)cls;
  return f2e_java_string(env, f2e_parse_process());
}

JNIEXPORT jstring JNICALL Java_com_oresoftware_flags2env_Flags2Env_parseJson(JNIEnv *env, jclass cls, jstring config_path, jobjectArray argv) {
  (void)cls;
  const char *config = (*env)->GetStringUTFChars(env, config_path, NULL);
  if (!config) {
    return (*env)->NewStringUTF(env, "{}");
  }

  jsize argc = argv ? (*env)->GetArrayLength(env, argv) : 0;
  const char **items = NULL;
  jstring *strings = NULL;
  if (argc > 0) {
    items = (const char **)calloc((size_t)argc, sizeof(char *));
    strings = (jstring *)calloc((size_t)argc, sizeof(jstring));
    if (!items || !strings) {
      free(items);
      free(strings);
      (*env)->ReleaseStringUTFChars(env, config_path, config);
      return (*env)->NewStringUTF(env, "{}");
    }
  }

  for (jsize i = 0; i < argc; i++) {
    strings[i] = (jstring)(*env)->GetObjectArrayElement(env, argv, i);
    if (strings[i]) {
      items[i] = (*env)->GetStringUTFChars(env, strings[i], NULL);
    }
  }

  char *json = f2e_parse_from_file(config, (int)argc, items);

  for (jsize i = 0; i < argc; i++) {
    if (strings[i] && items[i]) {
      (*env)->ReleaseStringUTFChars(env, strings[i], items[i]);
    }
    if (strings[i]) {
      (*env)->DeleteLocalRef(env, strings[i]);
    }
  }
  free(items);
  free(strings);
  (*env)->ReleaseStringUTFChars(env, config_path, config);

  return f2e_java_string(env, json);
}

JNIEXPORT jstring JNICALL Java_com_oresoftware_flags2env_Flags2Env_parseDefaultJson(JNIEnv *env, jclass cls, jobjectArray argv) {
  (void)cls;
  jsize argc = argv ? (*env)->GetArrayLength(env, argv) : 0;
  const char **items = NULL;
  jstring *strings = NULL;
  if (argc > 0) {
    items = (const char **)calloc((size_t)argc, sizeof(char *));
    strings = (jstring *)calloc((size_t)argc, sizeof(jstring));
    if (!items || !strings) {
      free(items);
      free(strings);
      return (*env)->NewStringUTF(env, "{}");
    }
  }

  for (jsize i = 0; i < argc; i++) {
    strings[i] = (jstring)(*env)->GetObjectArrayElement(env, argv, i);
    if (strings[i]) {
      items[i] = (*env)->GetStringUTFChars(env, strings[i], NULL);
    }
  }

  char *json = f2e_parse((int)argc, items);

  for (jsize i = 0; i < argc; i++) {
    if (strings[i] && items[i]) {
      (*env)->ReleaseStringUTFChars(env, strings[i], items[i]);
    }
    if (strings[i]) {
      (*env)->DeleteLocalRef(env, strings[i]);
    }
  }
  free(items);
  free(strings);

  return f2e_java_string(env, json);
}
