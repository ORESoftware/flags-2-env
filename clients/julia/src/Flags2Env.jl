module Flags2Env

using JSON3

export parse, parse_process, apply

function default_library_name()
    if Sys.isapple()
        return "libflags2env.dylib"
    elseif Sys.iswindows()
        return "flags2env.dll"
    end
    return "libflags2env.so"
end

function owned_string(ptr::Ptr{Cchar}, library_path::AbstractString)
    ptr == C_NULL && return Dict{String,String}()
    try
        raw = unsafe_string(ptr)
        parsed = JSON3.read(raw, Dict{String,String})
        return Dict(string(k) => string(v) for (k, v) in parsed)
    finally
        ccall((:f2e_free, library_path), Cvoid, (Ptr{Cchar},), ptr)
    end
end

function parse(argv; config_path=nothing, library_path=default_library_name())
    argv_json = JSON3.write([string(value) for value in argv])
    ptr = if config_path === nothing
        ccall((:f2e_parse_json_argv, library_path), Ptr{Cchar}, (Cstring,), argv_json)
    else
        ccall((:f2e_parse_json_argv_from_file, library_path), Ptr{Cchar}, (Cstring, Cstring), string(config_path), argv_json)
    end
    return owned_string(ptr, library_path)
end

function parse_process(; config_path=nothing, library_path=default_library_name())
    ptr = if config_path === nothing
        ccall((:f2e_parse_process, library_path), Ptr{Cchar}, ())
    else
        ccall((:f2e_parse_process_from_file, library_path), Ptr{Cchar}, (Cstring,), string(config_path))
    end
    return owned_string(ptr, library_path)
end

function apply(env::AbstractDict, argv; config_path=nothing, library_path=default_library_name())
    return merge(Dict(string(k) => string(v) for (k, v) in env), parse(argv; config_path=config_path, library_path=library_path))
end

end
