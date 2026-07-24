require "fiddle"
require "fiddle/import"
require "json"

module Flags2Env
  module Native
    extend Fiddle::Importer

    suffix = case RUBY_PLATFORM
             when /darwin/
               "dylib"
             when /mswin|mingw|cygwin/
               "dll"
             else
               "so"
    end

    dlload ENV.fetch("FLAGS2ENV_NATIVE_LIB", "libflags2env.#{suffix}")
    extern "char* f2e_parse_json_argv(char*)"
    extern "char* f2e_parse_json_argv_from_file(char*, char*)"
    extern "char* f2e_parse_process()"
    extern "char* f2e_parse_process_from_file(char*)"
    extern "int f2e_is_help_requested_json_argv(char*)"
    extern "char* f2e_help_table_for_json_argv(char*, char*, int)"
    extern "char* f2e_help_table_for_json_argv_from_file(char*, char*, char*, int)"
    extern "void f2e_free(char*)"
  end

  module_function

  def parse(argv = ARGV, config_path: nil)
    argv_json = JSON.generate(argv.map(&:to_s))
    result = config_path ? Native.f2e_parse_json_argv_from_file(config_path, argv_json) : Native.f2e_parse_json_argv(argv_json)
    return {} if result.null?

    JSON.parse(result.to_s).transform_values(&:to_s)
  ensure
    Native.f2e_free(result) if result && !result.null?
  end

  def parse_process(config_path: nil)
    result = config_path ? Native.f2e_parse_process_from_file(config_path) : Native.f2e_parse_process()
    return {} if result.null?

    JSON.parse(result.to_s).transform_values(&:to_s)
  ensure
    Native.f2e_free(result) if result && !result.null?
  end

  def help_requested?(argv = ARGV)
    argv_json = JSON.generate(argv.map(&:to_s))
    Native.f2e_is_help_requested_json_argv(argv_json) != 0
  end

  # Renders the help table for the [commands.*] path selected by argv; with no
  # matching command this renders the top-level menu including the Commands
  # section when subcommands are declared.
  def help_table(command, argv = ARGV, config_path: nil, terminal_columns: 0)
    argv_json = JSON.generate(argv.map(&:to_s))
    result = if config_path
               Native.f2e_help_table_for_json_argv_from_file(config_path, command.to_s, argv_json, terminal_columns)
             else
               Native.f2e_help_table_for_json_argv(command.to_s, argv_json, terminal_columns)
             end
    return "" if result.null?

    result.to_s
  ensure
    Native.f2e_free(result) if result && !result.null?
  end

  def apply(env = ENV.to_h, argv = ARGV, config_path: nil)
    env.merge(parse(argv, config_path: config_path))
  end

  def apply_process(env = ENV.to_h, config_path: nil)
    env.merge(parse_process(config_path: config_path))
  end
end
