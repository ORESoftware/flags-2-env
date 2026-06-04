function value = ownedString(alias, ptr)
if isempty(ptr)
    value = "{}";
    return
end

if isa(ptr, "lib.pointer")
    value = char(ptr.Value);
    calllib(alias, "f2e_free", ptr);
else
    value = char(ptr);
end
end
