require "json"

@[Link("flags2env")]
lib LibFlags2Env
  fun f2e_parse_json_argv(argv_json : LibC::Char*) : LibC::Char*
  fun f2e_parse_json_argv_from_file(config_path : LibC::Char*, argv_json : LibC::Char*) : LibC::Char*
  fun f2e_parse_process : LibC::Char*
  fun f2e_parse_process_from_file(config_path : LibC::Char*) : LibC::Char*
  fun f2e_free(value : LibC::Char*)
end

module Flags2Env
  VERSION = "0.1.0"

  def self.parse(argv : Enumerable, config_path : String? = nil) : Hash(String, String)
    argv_json = argv.map(&.to_s).to_json
    ptr = if config_path
            LibFlags2Env.f2e_parse_json_argv_from_file(config_path, argv_json)
          else
            LibFlags2Env.f2e_parse_json_argv(argv_json)
          end
    owned_map(ptr)
  end

  def self.parse_process(config_path : String? = nil) : Hash(String, String)
    ptr = config_path ? LibFlags2Env.f2e_parse_process_from_file(config_path) : LibFlags2Env.f2e_parse_process
    owned_map(ptr)
  end

  def self.apply(env : Hash(String, String), argv : Enumerable, config_path : String? = nil) : Hash(String, String)
    env.merge(parse(argv, config_path))
  end

  private def self.owned_map(ptr) : Hash(String, String)
    return {} of String => String if ptr.null?
    begin
      raw = String.new(ptr)
      parsed = JSON.parse(raw).as_h
      parsed.transform_values(&.as_s)
    ensure
      LibFlags2Env.f2e_free(ptr)
    end
  end
end
