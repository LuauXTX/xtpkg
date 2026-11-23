local path = require("system/path")
local Install = require("./Install")
local incoming = { ... }
local ok, err = pcall(function()
    local options, i = {}, 1
    while i <= #incoming do
        local arg = incoming[i]
        if arg == "--prefix" then
            i += 1; if not incoming[i] or incoming[i]:sub(1, 1) == "-" then error("--prefix needs a directory", 0) end
            options.prefix = incoming[i]
        elseif arg == "--no-path" then options.noPath = true
        elseif arg == "--recover" then options.recover = true
        elseif arg == "--help" or arg == "-h" then print("Usage: install.sh | install.cmd [--prefix directory] [--no-path] [--recover]"); return
        else error("Unknown installation argument: " .. arg, 0) end
        i += 1
    end
    local source = path.dirname(path.dirname(path.dirname(process.argv[2])))
    Install.run(source, options)
end)
if not ok then print("error: " .. tostring(err):gsub("\nstack traceback:.*", "")); process.exit(1) end
