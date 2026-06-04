function env = apply(env, argv, configPath, libraryPath, headerPath)
arguments
    env struct
    argv {mustBeText}
    configPath string = missing
    libraryPath string = flags2env.defaultLibraryName()
    headerPath string = flags2env.defaultHeaderPath()
end

parsed = flags2env.parse(argv, configPath, libraryPath, headerPath);
keys = fieldnames(parsed);
for i = 1:numel(keys)
    env.(keys{i}) = parsed.(keys{i});
end
end
