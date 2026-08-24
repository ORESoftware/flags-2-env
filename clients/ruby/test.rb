suffix = RUBY_PLATFORM.match?(/darwin/) ? "dylib" : RUBY_PLATFORM.match?(/mswin|mingw|cygwin/) ? "dll" : "so"
ENV["FLAGS2ENV_NATIVE_LIB"] = File.expand_path("../../build/libflags2env.#{suffix}", __dir__)

require "json"

require_relative "lib"

# Resolved before the chdir below, so the shared contract stays findable.
REPO_ROOT = File.expand_path("../..", __dir__)

Dir.chdir("../../tests/fixtures/nested/deeper")

parsed = Flags2Env.parse(["app", "--debug=t", "--port", "8181"])
raise "unexpected parsed map: #{parsed.inspect}" unless parsed["DEBUG"] == "true" && parsed["PORT"] == "8181" && parsed["COLOR"] == "true"

explicit = Flags2Env.parse(["app", "--debug=f"], config_path: "../../.cli-flags.toml")
raise "unexpected explicit config map: #{explicit.inspect}" unless explicit["DEBUG"] == "false" && explicit["PORT"] == "3000"

# Shared short-bundle contract. Combined single-character flags ("rm -rf",
# "set -eo pipefail", "node -pe") are the densest corner of the parser, and a
# binding that never parses one is green without having exercised the library.
# The case list is generated from the reference parser; see
# scripts/verify-bundle-contract.py.
contract = JSON.parse(File.read(File.join(REPO_ROOT, "tests/fixtures/bundle-contract.json")))
contract["cases"].each do |bundle_case|
  actual = Flags2Env.parse(bundle_case["argv"])
  next if actual == bundle_case["expect"]

  raise "bundle contract #{bundle_case["argv"].join(" ")}: expected " \
        "#{bundle_case["expect"].inspect}, got #{actual.inspect}"
end
raise "bundle contract looks truncated" unless contract["cases"].length >= 19

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

coerced = Flags2Env.coerce(
  { "GITISH_COMMAND" => "remote add", "GITISH_CMD_ADD" => "true", "GITISH_REMOTE_ADD_FETCH" => "true" },
  config_path: subcommands_config
)
unless coerced["GITISH_COMMAND"] == "remote add" && coerced["GITISH_CMD_ADD"] == true && coerced["GITISH_REMOTE_ADD_FETCH"] == true
  raise "unexpected coerced map: #{coerced.inspect}"
end

begin
  Flags2Env.coerce({ "GITISH_COMMAND" => 42 }, config_path: subcommands_config)
  raise "expected CoercionError"
rescue Flags2Env::CoercionError => e
  raise "unexpected coercion error: #{e.message}" unless e.message.include?("command_env")
end

generated = Flags2Env.generate_types("typescript", type_name: "GitishConfig", config_path: subcommands_config)
unless generated.include?("GITISH_COMMAND?: string;") && generated.include?("GITISH_CMD_ADD?: boolean;")
  raise "unexpected generated types:\n#{generated}"
end

puts "ruby client extended tests passed"
