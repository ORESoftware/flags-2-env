let parsed =
  Flags2Env.parse(
    ~configPath="tests/fixtures/.cli-flags.toml",
    ~argv=["app", "--debug=t", "--port", "8181"],
  );

let get = key => List.assoc(key, parsed);

if (get("DEBUG") != "true" || get("PORT") != "8181") {
  failwith("unexpected parsed map");
};
