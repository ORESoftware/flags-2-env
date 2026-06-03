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

  def apply(env = ENV.to_h, argv = ARGV, config_path: nil)
    env.merge(parse(argv, config_path: config_path))
  end

  def apply_process(env = ENV.to_h, config_path: nil)
    env.merge(parse_process(config_path: config_path))
  end
end
