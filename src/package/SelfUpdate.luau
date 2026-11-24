local fs = require("system/fs")
local path = require("system/path")
local Util = require("./Util")
local Manifest = require("./Manifest")
local Lockfile = require("./Lockfile")
local Config = require("./Config")
local Launchers = require("./Launchers")
local SelfUpdate = {}
local repositories = { ["https://github.com/mintiler-dev/xtpkg"] = true, ["https://github.com/luauxtx/xtpkg"] = true }
local function repository(url)
    return type(url) == "string" and repositories[url:lower():gsub("/$", ""):gsub("%.git$", "")] == true
end
function SelfUpdate.official(package, manifest)
    return package.name == "xtpkg" and manifest.package.name == "xtpkg" and package.version == manifest.package.version
        and package.registry ~= nil and not package.external and not package.localSource
        and type(package.source) == "string" and package.source:sub(1, 4) == "git+" and repository(package.source:sub(5))
        and repository(manifest.package.repository) and manifest.package.entry == "src/main.luau" and manifest.bin.xtpkg == "src/main.luau"
end
function SelfUpdate.context()
    local root = process.getenv("XTPKG_HOST_ROOT") or path.dirname(path.dirname(Util.absolute(process.cwd(), process.argv[2])))
    root = Util.absolute(process.cwd(), root)
    local bootstrap = path.join(root, "src", "bootstrap.luau")
    Util.noLinks(bootstrap)
    if not fs.exists(bootstrap) then error("Reinstall XTPKG once with install.cmd/install.sh to enable package-based self-updates", 0) end
    return { root = root, bootstrap = bootstrap, allowed = {} }
end
function SelfUpdate.launcher(package, manifest, runtime)
    if not SelfUpdate.official(package, manifest) then error("The xtpkg executable is reserved for the official registry package xtpkg with its original HTTPS source and src/main.luau entrypoint", 0) end
    local context = SelfUpdate.context()
    local marker = path.join(context.root, ".xtpkg-app")
    if fs.exists(marker) then
        Util.noLinks(marker)
        if fs.readSync(marker) ~= "xtpkg-app-v1\n" then error("Invalid XTPKG host ownership marker", 0) end
        local bin = path.join(path.dirname(context.root), "bin")
        Launchers.verify(bin)
        local launcher = path.join(bin, "xtpkg" .. (Launchers.windows() and ".cmd" or ""))
        local expected = Launchers.render(runtime, context.bootstrap, Launchers.windows())
        if not fs.exists(launcher) or fs.readSync(launcher) ~= expected then error("The installed XTPKG launcher needs a one-time reinstall with install.cmd/install.sh before self-updating", 0) end
        local key = path.normalize(bin); if Launchers.windows() then key = key:lower() end
        context.allowed[key] = true
    end
    return context.bootstrap, context.allowed
end
function SelfUpdate.selection()
    local directory = Config.global()
    local marker = path.join(directory, ".xtpkg-global"); Util.noLinks(marker)
    if not fs.exists(marker) then return nil end
    if fs.readSync(marker) ~= "xtpkg-global-v1\n" then error("Invalid global ownership marker", 0) end
    local lock = Lockfile.load(directory)
    if not lock or lock.legacy or not lock.roots.xtpkg or not lock.packages.xtpkg then return nil end
    local package = lock.packages.xtpkg
    local location = path.join(directory, "packages", "xtpkg")
    if not Manifest.exists(location) then return nil end
    local manifest = Manifest.load(location)
    -- A killed replacement can temporarily disagree with the old lock. Keep the
    -- host CLI usable for recovery rather than executing a partial selection.
    if not SelfUpdate.official(package, manifest) then return nil end
    local entry = path.join(location, "src", "main.luau"); Util.noLinks(entry)
    if not fs.exists(entry) then return nil end
    return { entry = entry, version = package.version, modern = fs.exists(path.join(location, "src", "package", "SelfUpdate.luau")) }
end
return SelfUpdate
