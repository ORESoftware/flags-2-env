function env = parse(argv, configPath, libraryPath, headerPath)
arguments
    argv {mustBeText}
    configPath string = missing
    libraryPath string = flags2env.defaultLibraryName()
    headerPath string = fullfile(pwd, "src", "parser.h")
end

alias = flags2env.ensureLoaded(libraryPath, headerPath);
argvJson = jsonencode(cellstr(string(argv)));

if ismissing(configPath)
    raw = flags2env.ownedString(alias, calllib(alias, "f2e_parse_json_argv", argvJson));
else
    raw = flags2env.ownedString(alias, calllib(alias, "f2e_parse_json_argv_from_file", char(configPath), argvJson));
end

env = jsondecode(raw);
end
