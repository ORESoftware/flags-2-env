let parse = (~configPath=?, argv) => Flags2env.parse(?config_path=configPath, argv);

let parseProcess = (~configPath=?, ()) =>
  Flags2env.parse_process(?config_path=configPath, ());

let apply = (env, argv) => Flags2env.apply(env, argv);
