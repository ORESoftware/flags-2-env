function name = defaultLibraryName()
if ismac
    name = "libflags2env.dylib";
elseif ispc
    name = "flags2env.dll";
else
    name = "libflags2env.so";
end
end
