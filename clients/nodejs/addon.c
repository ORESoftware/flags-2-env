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

static int f2e_node_read_optional_string(napi_env env, napi_value value, char **out) {
  *out = NULL;
  if (!value) {
    return 1;
  }

  napi_valuetype type;
  if (napi_typeof(env, value, &type) != napi_ok) {
    return 0;
  }
  if (type == napi_undefined || type == napi_null) {
    return 1;
  }
  return f2e_node_read_string(env, value, out);
}

static int f2e_node_read_optional_int(napi_env env, napi_value value, int *out) {
  *out = 0;
  if (!value) {
    return 1;
  }

  napi_valuetype type;
  if (napi_typeof(env, value, &type) != napi_ok) {
    return 0;
  }
  if (type == napi_undefined || type == napi_null) {
    return 1;
  }
  return napi_get_value_int32(env, value, out) == napi_ok;
}

static napi_value f2e_node_string_result(napi_env env, char *result, const char *message) {
  if (!result) {
    return f2e_node_throw(env, message);
  }

  napi_value out;
  napi_create_string_utf8(env, result, NAPI_AUTO_LENGTH, &out);
  f2e_free(result);
  return out;
}

static napi_value f2e_node_int_result(napi_env env, int value) {
  napi_value out;
  napi_create_int32(env, value, &out);
  return out;
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

static napi_value f2e_node_audit_config_json(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  char *config_path = NULL;
  if (argc >= 1 && !f2e_node_read_optional_string(env, args[0], &config_path)) {
    return f2e_node_throw(env, "configPath must be a string");
  }

  char *result = config_path ? f2e_audit_config_from_file(config_path) : f2e_audit_config();
  free(config_path);
  return f2e_node_string_result(env, result, "failed to audit config");
}

static napi_value f2e_node_audit_config_status(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  char *config_path = NULL;
  if (argc >= 1 && !f2e_node_read_optional_string(env, args[0], &config_path)) {
    return f2e_node_throw(env, "configPath must be a string");
  }

  int status = config_path ? f2e_audit_config_status_from_file(config_path) : f2e_audit_config_status();
  free(config_path);
  return f2e_node_int_result(env, status);
}

static napi_value f2e_node_audit_env_json(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  char *config_path = NULL;
  char *env_path = NULL;
  if (argc >= 1 && !f2e_node_read_optional_string(env, args[0], &config_path)) {
    return f2e_node_throw(env, "configPath must be a string");
  }
  if (argc >= 2 && !f2e_node_read_optional_string(env, args[1], &env_path)) {
    free(config_path);
    return f2e_node_throw(env, "envPath must be a string");
  }

  char *result = config_path ? f2e_audit_env_file_from_file(config_path, env_path) : f2e_audit_env_file();
  free(config_path);
  free(env_path);
  return f2e_node_string_result(env, result, "failed to audit env file");
}

static napi_value f2e_node_audit_env_status(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  char *config_path = NULL;
  char *env_path = NULL;
  if (argc >= 1 && !f2e_node_read_optional_string(env, args[0], &config_path)) {
    return f2e_node_throw(env, "configPath must be a string");
  }
  if (argc >= 2 && !f2e_node_read_optional_string(env, args[1], &env_path)) {
    free(config_path);
    return f2e_node_throw(env, "envPath must be a string");
  }

  int status = config_path ? f2e_audit_env_file_status_from_file(config_path, env_path) : f2e_audit_env_file_status();
  free(config_path);
  free(env_path);
  return f2e_node_int_result(env, status);
}

static napi_value f2e_node_completion_script(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  if (argc < 1) {
    return f2e_node_throw(env, "completionScript(shell, command?, configPath?) requires shell");
  }

  char *shell = NULL;
  char *command = NULL;
  char *config_path = NULL;
  if (!f2e_node_read_string(env, args[0], &shell)) {
    return f2e_node_throw(env, "shell must be a string");
  }
  if (argc >= 2 && !f2e_node_read_optional_string(env, args[1], &command)) {
    free(shell);
    return f2e_node_throw(env, "command must be a string");
  }
  if (argc >= 3 && !f2e_node_read_optional_string(env, args[2], &config_path)) {
    free(shell);
    free(command);
    return f2e_node_throw(env, "configPath must be a string");
  }

  char *result = config_path ? f2e_completion_script_from_file(config_path, shell, command) : f2e_completion_script(shell, command);
  free(shell);
  free(command);
  free(config_path);
  return f2e_node_string_result(env, result, "failed to generate completion script");
}

static napi_value f2e_node_generate_types(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  if (argc < 1) {
    return f2e_node_throw(env, "generateTypes(language, typeName?, configPath?) requires language");
  }

  char *language = NULL;
  char *type_name = NULL;
  char *config_path = NULL;
  if (!f2e_node_read_string(env, args[0], &language)) {
    return f2e_node_throw(env, "language must be a string");
  }
  if (argc >= 2 && !f2e_node_read_optional_string(env, args[1], &type_name)) {
    free(language);
    return f2e_node_throw(env, "typeName must be a string");
  }
  if (argc >= 3 && !f2e_node_read_optional_string(env, args[2], &config_path)) {
    free(language);
    free(type_name);
    return f2e_node_throw(env, "configPath must be a string");
  }

  char *result = config_path ? f2e_generate_types_from_file(config_path, language, type_name)
                             : f2e_generate_types(language, type_name);
  free(language);
  free(type_name);
  free(config_path);
  return f2e_node_string_result(env, result, "failed to generate types");
}

static napi_value f2e_node_coerce_json(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  if (argc < 1) {
    return f2e_node_throw(env, "coerceJson(valuesJson, configPath?) requires valuesJson");
  }

  char *values_json = NULL;
  char *config_path = NULL;
  if (!f2e_node_read_string(env, args[0], &values_json)) {
    return f2e_node_throw(env, "valuesJson must be a string");
  }
  if (argc >= 2 && !f2e_node_read_optional_string(env, args[1], &config_path)) {
    free(values_json);
    return f2e_node_throw(env, "configPath must be a string");
  }

  char *result = config_path ? f2e_coerce_json_from_file(config_path, values_json)
                             : f2e_coerce_json(values_json);
  free(values_json);
  free(config_path);
  return f2e_node_string_result(env, result, "failed to coerce values");
}

static napi_value f2e_node_parse_structured_json(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  if (argc < 1) {
    return f2e_node_throw(env, "parseStructuredJson(argvJson, configPath?) requires argvJson");
  }

  char *argv_json = NULL;
  char *config_path = NULL;
  if (!f2e_node_read_string(env, args[0], &argv_json)) {
    return f2e_node_throw(env, "argvJson must be a string");
  }
  if (argc >= 2 && !f2e_node_read_optional_string(env, args[1], &config_path)) {
    free(argv_json);
    return f2e_node_throw(env, "configPath must be a string");
  }

  char *result = config_path ? f2e_parse_structured_json_argv_from_file(config_path, argv_json)
                             : f2e_parse_structured_json_argv(argv_json);
  free(argv_json);
  free(config_path);
  return f2e_node_string_result(env, result, "failed to parse argv");
}

static napi_value f2e_node_resolve_commands_json(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  if (argc < 1) {
    return f2e_node_throw(env, "resolveCommandsJson(argvJson, configPath?) requires argvJson");
  }

  char *argv_json = NULL;
  char *config_path = NULL;
  if (!f2e_node_read_string(env, args[0], &argv_json)) {
    return f2e_node_throw(env, "argvJson must be a string");
  }
  if (argc >= 2 && !f2e_node_read_optional_string(env, args[1], &config_path)) {
    free(argv_json);
    return f2e_node_throw(env, "configPath must be a string");
  }

  char *result = config_path ? f2e_resolve_commands_json_argv_from_file(config_path, argv_json)
                             : f2e_resolve_commands_json_argv(argv_json);
  free(argv_json);
  free(config_path);
  return f2e_node_string_result(env, result, "failed to resolve commands");
}

static napi_value f2e_node_is_help_json(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  if (argc < 1) {
    return f2e_node_throw(env, "isHelpJson(argvJson) requires argvJson");
  }

  char *argv_json = NULL;
  if (!f2e_node_read_string(env, args[0], &argv_json)) {
    return f2e_node_throw(env, "argvJson must be a string");
  }

  int requested = f2e_is_help_requested_json_argv(argv_json);
  free(argv_json);

  napi_value out;
  napi_get_boolean(env, requested != 0, &out);
  return out;
}

static napi_value f2e_node_help_table(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  char *command = NULL;
  char *config_path = NULL;
  int terminal_columns = 0;
  if (argc >= 1 && !f2e_node_read_optional_string(env, args[0], &command)) {
    return f2e_node_throw(env, "command must be a string");
  }
  if (argc >= 2 && !f2e_node_read_optional_int(env, args[1], &terminal_columns)) {
    free(command);
    return f2e_node_throw(env, "terminalColumns must be a number");
  }
  if (argc >= 3 && !f2e_node_read_optional_string(env, args[2], &config_path)) {
    free(command);
    return f2e_node_throw(env, "configPath must be a string");
  }

  char *result = config_path ? f2e_help_table_from_file(config_path, command, terminal_columns)
                             : f2e_help_table(command, terminal_columns);
  free(command);
  free(config_path);
  return f2e_node_string_result(env, result, "failed to generate help table");
}

static napi_value f2e_node_help_table_for_argv(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  if (argc < 2) {
    return f2e_node_throw(env, "helpTableForArgv(command, argvJson, terminalColumns?, configPath?) requires command and argvJson");
  }

  char *command = NULL;
  char *argv_json = NULL;
  char *config_path = NULL;
  int terminal_columns = 0;
  if (!f2e_node_read_optional_string(env, args[0], &command)) {
    return f2e_node_throw(env, "command must be a string");
  }
  if (!f2e_node_read_string(env, args[1], &argv_json)) {
    free(command);
    return f2e_node_throw(env, "argvJson must be a string");
  }
  if (argc >= 3 && !f2e_node_read_optional_int(env, args[2], &terminal_columns)) {
    free(command);
    free(argv_json);
    return f2e_node_throw(env, "terminalColumns must be a number");
  }
  if (argc >= 4 && !f2e_node_read_optional_string(env, args[3], &config_path)) {
    free(command);
    free(argv_json);
    return f2e_node_throw(env, "configPath must be a string");
  }

  char *result = config_path
                     ? f2e_help_table_for_json_argv_from_file(config_path, command, argv_json, terminal_columns)
                     : f2e_help_table_for_json_argv(command, argv_json, terminal_columns);
  free(command);
  free(argv_json);
  free(config_path);
  return f2e_node_string_result(env, result, "failed to generate help table");
}

static napi_value f2e_node_parse_process_json(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);

  char *config_path = NULL;
  char *result = NULL;
  if (argc >= 1) {
    if (!f2e_node_read_string(env, args[0], &config_path)) {
      return f2e_node_throw(env, "configPath must be a string");
    }
    result = f2e_parse_process_from_file(config_path);
  } else {
    result = f2e_parse_process();
  }

  free(config_path);

  if (!result) {
    return f2e_node_throw(env, "failed to parse process flags");
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

  napi_value parse_process_json;
  napi_create_function(env, "parseProcessJson", NAPI_AUTO_LENGTH, f2e_node_parse_process_json, NULL, &parse_process_json);
  napi_set_named_property(env, exports, "parseProcessJson", parse_process_json);

  napi_value audit_config_json;
  napi_create_function(env, "auditConfigJson", NAPI_AUTO_LENGTH, f2e_node_audit_config_json, NULL, &audit_config_json);
  napi_set_named_property(env, exports, "auditConfigJson", audit_config_json);

  napi_value audit_config_status;
  napi_create_function(env, "auditConfigStatus", NAPI_AUTO_LENGTH, f2e_node_audit_config_status, NULL, &audit_config_status);
  napi_set_named_property(env, exports, "auditConfigStatus", audit_config_status);

  napi_value audit_env_json;
  napi_create_function(env, "auditEnvJson", NAPI_AUTO_LENGTH, f2e_node_audit_env_json, NULL, &audit_env_json);
  napi_set_named_property(env, exports, "auditEnvJson", audit_env_json);

  napi_value audit_env_status;
  napi_create_function(env, "auditEnvStatus", NAPI_AUTO_LENGTH, f2e_node_audit_env_status, NULL, &audit_env_status);
  napi_set_named_property(env, exports, "auditEnvStatus", audit_env_status);

  napi_value completion_script;
  napi_create_function(env, "completionScript", NAPI_AUTO_LENGTH, f2e_node_completion_script, NULL, &completion_script);
  napi_set_named_property(env, exports, "completionScript", completion_script);

  napi_value generate_types;
  napi_create_function(env, "generateTypes", NAPI_AUTO_LENGTH, f2e_node_generate_types, NULL, &generate_types);
  napi_set_named_property(env, exports, "generateTypes", generate_types);

  napi_value coerce_json;
  napi_create_function(env, "coerceJson", NAPI_AUTO_LENGTH, f2e_node_coerce_json, NULL, &coerce_json);
  napi_set_named_property(env, exports, "coerceJson", coerce_json);

  napi_value is_help_json;
  napi_create_function(env, "isHelpJson", NAPI_AUTO_LENGTH, f2e_node_is_help_json, NULL, &is_help_json);
  napi_set_named_property(env, exports, "isHelpJson", is_help_json);

  napi_value resolve_commands_json;
  napi_create_function(env, "resolveCommandsJson", NAPI_AUTO_LENGTH, f2e_node_resolve_commands_json, NULL, &resolve_commands_json);
  napi_set_named_property(env, exports, "resolveCommandsJson", resolve_commands_json);

  napi_value parse_structured_json;
  napi_create_function(env, "parseStructuredJson", NAPI_AUTO_LENGTH, f2e_node_parse_structured_json, NULL, &parse_structured_json);
  napi_set_named_property(env, exports, "parseStructuredJson", parse_structured_json);

  napi_value help_table;
  napi_create_function(env, "helpTable", NAPI_AUTO_LENGTH, f2e_node_help_table, NULL, &help_table);
  napi_set_named_property(env, exports, "helpTable", help_table);

  napi_value help_table_for_argv;
  napi_create_function(env, "helpTableForArgv", NAPI_AUTO_LENGTH, f2e_node_help_table_for_argv, NULL, &help_table_for_argv);
  napi_set_named_property(env, exports, "helpTableForArgv", help_table_for_argv);
  return exports;
}

NAPI_MODULE(NODE_GYP_MODULE_NAME, f2e_node_init)
