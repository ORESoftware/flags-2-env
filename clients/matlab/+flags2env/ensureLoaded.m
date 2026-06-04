function alias = ensureLoaded(libraryPath, headerPath)
arguments
    libraryPath string = flags2env.defaultLibraryName()
    headerPath string = flags2env.defaultHeaderPath()
end

alias = "flags2env";
if ~libisloaded(alias)
    loadlibrary(libraryPath, headerPath, "alias", alias);
end
end
