local fs = require("system/fs")
local path = require("system/path")
local Config = require("./Config")
local Util = require("./Util")
local Manifest = require("./Manifest")
local Launchers = require("./Launchers")
local Global = {}
function Global.ensure()
    local root = Config.global(); Util.noLinks(root)
    local marker = path.join(root, ".xtpkg-global")
    if fs.exists(marker) then
        Util.noLinks(marker)
        if fs.readSync(marker) ~= "xtpkg-global-v1\n" then error("Invalid global directory ownership marker", 0) end
        return root
    end
    if fs.exists(root) and #fs.readDir(root):await() ~= 0 then error("Refusing to adopt an unmanaged global directory: " .. root, 0) end
    Util.mkdir(root)
    -- Initialization uses its own guard so concurrent first-use cannot race.
    local guard = path.join(root, ".xtpkg-initialize")
    fs.mkdir(guard, false):await()
    local ok, err = pcall(function()
        if Manifest.exists(root) then error("Global initialization is incomplete; inspect " .. root, 0) end
        Manifest.save(root, { package = { name = "xtpkg-global", version = "1.0.0", entry = "main.luau" }, dependencies = {}, scripts = {} })
        fs.writeSync(path.join(root, "main.luau"), "return {}\n")
        fs.writeSync(marker, "xtpkg-global-v1\n")
    end)
    fs.remove(guard):await()
    if not ok then error(err, 0) end
    return root
end
function Global.run(args, callback)
    local caller = process.cwd(); local root = Global.ensure()
    args.callerDirectory = caller
    local ok, result = pcall(function() process.chdir(root); return callback() end)
    process.chdir(caller)
    if not ok then error(result, 0) end
    if args._[1] ~= "list" then
        local bin = path.join(root, "bin")
        local found = false
        local separator = Launchers.windows() and ";" or ":"
        for dir in (process.getenv("PATH") or ""):gmatch("[^" .. separator .. "]+") do if path.normalize(dir):lower() == bin:lower() then found = true end end
        if not found then args.log("Global launchers: " .. bin .. "\nRun the XTPKG installer to configure PATH, or add this directory to PATH yourself.") end
    end
    return result
end
return Global
