function env = parseProcess(configPath, libraryPath, headerPath)
arguments
    configPath string = missing
    libraryPath string = flags2env.defaultLibraryName()
    headerPath string = flags2env.defaultHeaderPath()
end

alias = flags2env.ensureLoaded(libraryPath, headerPath);
if ismissing(configPath)
    raw = flags2env.ownedString(alias, calllib(alias, "f2e_parse_process"));
else
    raw = flags2env.ownedString(alias, calllib(alias, "f2e_parse_process_from_file", char(configPath)));
end

env = jsondecode(raw);
end
