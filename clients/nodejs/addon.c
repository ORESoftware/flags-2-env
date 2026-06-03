#include "../../src/parser.h"

#include <node_api.h>
#include <stdlib.h>

static napi_value f2e_node_throw(napi_env env, const char *message) {
  napi_throw_error(env, NULL, message);
  return NULL;
}

static int f2e_node_read_string(napi_env env, napi_value value, char **out) {
  size_t len = 0;
  napi_status status = napi_get_value_string_utf8(env, value, NULL, 0, &len);
  if (status != napi_ok) {
    return 0;
  }
  char *buffer = (char *)malloc(len + 1);
  if (!buffer) {
    return 0;
  }
  status = napi_get_value_string_utf8(env, value, buffer, len + 1, &len);
  if (status != napi_ok) {
    free(buffer);
    return 0;
  }
  *out = buffer;
  return 1;
}

static napi_value f2e_node_parse_json(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  if (argc < 1) {
    return f2e_node_throw(env, "parseJson(argvJson, configPath?) requires argvJson");
  }

  char *argv_json = NULL;
  char *config_path = NULL;
  if (!f2e_node_read_string(env, args[0], &argv_json)) {
    return f2e_node_throw(env, "argvJson must be a string");
  }

  char *result = NULL;
  if (argc >= 2) {
    if (!f2e_node_read_string(env, args[1], &config_path)) {
      free(argv_json);
      return f2e_node_throw(env, "configPath must be a string");
    }
    result = f2e_parse_json_argv_from_file(config_path, argv_json);
  } else {
    result = f2e_parse_json_argv(argv_json);
  }

  free(argv_json);
  free(config_path);

  if (!result) {
    return f2e_node_throw(env, "failed to parse flags");
  }

  napi_value out;
  napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &out);
  f2e_free(result);
  return out;
}

static napi_value f2e_node_init(napi_env env, napi_value exports) {
  napi_value parse_json;
  napi_create_function(env, "parseJson", NAPI_AUTO_LENGTH, f2e_node_parse_json, NULL, &parse_json);
  napi_set_named_property(env, exports, "parseJson", parse_json);
  return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, f2e_node_init)
