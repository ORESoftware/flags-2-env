function path = defaultHeaderPath()
packageDir = fileparts(mfilename("fullpath"));
clientDir = fileparts(packageDir);
path = fullfile(clientDir, "native", "parser.h");
end
