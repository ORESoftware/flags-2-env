function alias = ensureLoaded(libraryPath, headerPath)
arguments
    libraryPath string = flags2env.defaultLibraryName()
    headerPath string = fullfile(pwd, "src", "parser.h")
end

alias = "flags2env";
if ~libisloaded(alias)
    loadlibrary(libraryPath, headerPath, "alias", alias);
end
end
