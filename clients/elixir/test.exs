File.cd!("../../tests/fixtures/nested/deeper")

parsed = Flags2Env.parse(["app", "--debug=t", "--port", "8181"])

unless parsed["DEBUG"] == "true" and parsed["PORT"] == "8181" and parsed["COLOR"] == "true" do
  IO.inspect(parsed, label: "unexpected parsed map")
  System.halt(1)
end
