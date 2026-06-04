let configPath = Filename.temp_file("flags2env-reason-smoke", ".toml");
let out = open_out(configPath);
output_string(
  out,
  {|
[flags.port]
env = "PORT"
aliases = ["port"]
type = "integer"

[flags.debug]
env = "DEBUG"
aliases = ["debug"]
type = "bool"
true_aliases = ["t"]
|},
);
close_out(out);

let parsed =
  Flags2Env.parse(
    ~configPath,
    ~argv=["app", "--debug=t", "--port", "8181"],
  );

let get = key => List.assoc(key, parsed);

if (get("DEBUG") != "true" || get("PORT") != "8181") {
  failwith("unexpected parsed map");
};
