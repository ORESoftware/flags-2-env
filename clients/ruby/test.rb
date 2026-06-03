suffix = RUBY_PLATFORM.match?(/darwin/) ? "dylib" : RUBY_PLATFORM.match?(/mswin|mingw|cygwin/) ? "dll" : "so"
ENV["FLAGS2ENV_NATIVE_LIB"] = File.expand_path("../../build/libflags2env.#{suffix}", __dir__)

require_relative "lib"

Dir.chdir("../../tests/fixtures/nested/deeper")

parsed = Flags2Env.parse(["app", "--debug=t", "--port", "8181"])
raise "unexpected parsed map: #{parsed.inspect}" unless parsed["DEBUG"] == "true" && parsed["PORT"] == "8181" && parsed["COLOR"] == "true"
