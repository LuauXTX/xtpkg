local fs = require("system/fs")
local path = require("system/path")
local Manifest = require("../package/Manifest")
local Util = require("../package/Util")
local ProjectInit = require("../package/ProjectInit")

local init = {}

function init.run(args)
    if args._[3] then error("Usage: xtpkg init [name] [--force] [--no-git] [--no-gitignore]", 0) end
    local cwd = process.cwd()
    local src = path.join(cwd, "src")
    local entry = path.join(src, "main.luau")
    Util.noLinks(src); Util.noLinks(entry)
    local ignore = not args["no-gitignore"] and ProjectInit.prepareIgnore(cwd) or nil
    Manifest.create(cwd, { name = args._[2] or path.basename(cwd), force = args.force or args.f })
    if not fs.exists(src) then fs.mkdir(src, true):await() end
    if not fs.exists(entry) then
        fs.writeSync(entry, "print(\"Hello from LuauXTX!\")\n")
    end
    args.log("Created xtpkg.toml")
    if ignore and ignore() > 0 then args.log("Appended missing .gitignore entries") end
    if not args["no-git"] then ProjectInit.git(cwd, args.log) end
end

return init
