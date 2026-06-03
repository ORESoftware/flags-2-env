File.cd!("../../tests/fixtures/nested/deeper")

parsed = Flags2Env.parse(["app", "--debug=t", "--port", "8181"])

unless parsed["DEBUG"] == "true" and parsed["PORT"] == "8181" and parsed["COLOR"] == "true" do
  IO.inspect(parsed, label: "unexpected parsed map")
  System.halt(1)
end

explicit = Flags2Env.parse(["app", "--debug=f"], "../../.cli-flags.toml")

unless explicit["DEBUG"] == "false" and explicit["PORT"] == "3000" do
  IO.inspect(explicit, label: "unexpected explicit config map")
  System.halt(1)
end

combined = Flags2Env.apply(["app", "--port", "8181"], %{"PORT" => "env", "KEEP" => "1"})

unless combined["PORT"] == "8181" and combined["KEEP"] == "1" and combined["COLOR"] == "true" do
  IO.inspect(combined, label: "unexpected combined map")
  System.halt(1)
end
