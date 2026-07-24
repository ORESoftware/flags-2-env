suffix = RUBY_PLATFORM.match?(/darwin/) ? "dylib" : RUBY_PLATFORM.match?(/mswin|mingw|cygwin/) ? "dll" : "so"
ENV["FLAGS2ENV_NATIVE_LIB"] = File.expand_path("../../build/libflags2env.#{suffix}", __dir__)

require_relative "lib"

Dir.chdir("../../tests/fixtures/nested/deeper")

parsed = Flags2Env.parse(["app", "--debug=t", "--port", "8181"])
raise "unexpected parsed map: #{parsed.inspect}" unless parsed["DEBUG"] == "true" && parsed["PORT"] == "8181" && parsed["COLOR"] == "true"

explicit = Flags2Env.parse(["app", "--debug=f"], config_path: "../../.cli-flags.toml")
raise "unexpected explicit config map: #{explicit.inspect}" unless explicit["DEBUG"] == "false" && explicit["PORT"] == "3000"

combined = Flags2Env.apply({ "PORT" => "env", "KEEP" => "1" }, ["app", "--port", "8181"])
raise "unexpected combined map: #{combined.inspect}" unless combined["PORT"] == "8181" && combined["KEEP"] == "1" && combined["COLOR"] == "true"

subcommands_config = "../../../subcommands/.cli-flags.toml"
scoped = Flags2Env.parse(["gitish", "add", "-A"], config_path: subcommands_config)
raise "unexpected scoped map: #{scoped.inspect}" unless scoped["GITISH_COMMAND"] == "add" && scoped["GITISH_ADD_ALL"] == "true"

raise "help detection failed" unless Flags2Env.help_requested?(["gitish", "add", "--help"])
raise "help false positive" if Flags2Env.help_requested?(["gitish", "add"])

scoped_help = Flags2Env.help_table("gitish", ["gitish", "remote", "add", "--help"],
                                   config_path: subcommands_config, terminal_columns: 100)
unless scoped_help.include?("Command: gitish remote add [OPTIONS]") && scoped_help.include?("--fetch")
  raise "unexpected scoped help:\n#{scoped_help}"
end

top_help = Flags2Env.help_table("gitish", ["gitish"], config_path: subcommands_config, terminal_columns: 100)
unless top_help.include?("Commands:") && top_help.include?("remote add")
  raise "unexpected top-level help:\n#{top_help}"
end

puts "ruby client tests passed"
