local fs = require("system/fs")
local path = require("system/path")
local Config = require("../package/Config")
local Manifest = require("../package/Manifest")
local Util = require("../package/Util")
local Json = require("../package/Json")
local Launchers = require("../package/Launchers")
local PathSetup = require("./PathSetup")
local Install = {}
local appMarker, operationMarker = "xtpkg-app-v1\n", "xtpkg-setup-v1\n"

local function ownedApp(directory)
    Util.noLinksTree(directory)
    if not fs.exists(directory) then return end
    local marker = path.join(directory, ".xtpkg-app")
    if not fs.exists(marker) or fs.readSync(marker) ~= appMarker then error("Refusing to overwrite an unmanaged app directory: " .. directory, 0) end
end
local function journal(work, state)
    local temporary = path.join(work, "journal.new")
    fs.writeSync(temporary, Json.pretty(state))
    fs.rename(temporary, path.join(work, "journal.json")):await()
end
local function restore(prefix, work, state)
    if state.committed then return end
    for _, name in ipairs({ "bin", "app" }) do
        local target, backup, staged = path.join(prefix, name), path.join(work, "old-" .. name), path.join(work, name)
        if fs.exists(backup) then
            if name == "app" then ownedApp(target); ownedApp(backup) else Launchers.verify(target); Launchers.verify(backup) end
            Util.remove(target); fs.rename(backup, target):await()
        elseif not state[name] and not fs.exists(staged) and fs.exists(target) then
            if name == "app" then ownedApp(target) else Launchers.verify(target) end
            Util.remove(target)
        elseif state[name] and not fs.exists(target) then error("Recovery needs manual inspection: missing " .. name .. " in " .. prefix, 0) end
    end
end
function Install.recover(prefix, work)
    Util.noLinksTree(work)
    local marker = path.join(work, ".xtpkg-setup")
    if not fs.exists(marker) then
        if #fs.readDir(work):await() == 0 then fs.remove(work):await(); return end
        error("Unrecognized setup operation directory; inspect it manually: " .. work, 0)
    end
    if fs.readSync(marker) ~= operationMarker then error("Invalid setup operation ownership marker", 0) end
    local filename = path.join(work, "journal.json")
    if fs.exists(filename) then
        if fs.stat(filename):await().size > 65536 then error("Invalid setup journal", 0) end
        local state = Json.decode(fs.readSync(filename), 65536)
        if not Json.object(state) or state.version ~= 1 or type(state.app) ~= "boolean" or type(state.bin) ~= "boolean" or type(state.committed) ~= "boolean" then error("Invalid setup journal; preserve backups for manual recovery", 0) end
        restore(prefix, work, state)
    end
    Util.remove(work)
end
function Install.run(source, options)
    options = options or {}
    source = Util.absolute(process.cwd(), source)
    local prefix = Util.absolute(process.cwd(), options.prefix or Config.data())
    if prefix:find("[%c]") then error("Control character in install prefix", 0) end
    local function overlap(a, b)
        if Launchers.windows() then a, b = a:lower(), b:lower() end
        return a == b or a:sub(1, #b + 1) == b .. "/" or b:sub(1, #a + 1) == a .. "/"
    end
    for _, name in ipairs({ "app", "bin" }) do
        for _, userDirectory in ipairs({ Config.home(), Config.cache(), Config.global() }) do
            if overlap(path.join(prefix, name), Util.absolute(process.cwd(), userDirectory)) then error("Install target overlaps configuration, cache, or global packages", 0) end
        end
    end
    Util.noLinks(prefix); Util.mkdir(prefix)
    local work = path.join(prefix, ".xtpkg-setup-operation")
    if fs.exists(work) then
        if not options.recover then error("Another/interrupted setup operation exists. After ensuring no installer is running, rerun with --recover. Backups: " .. work, 0) end
        Install.recover(prefix, work)
    end
    fs.mkdir(work, false):await()
    fs.writeSync(path.join(work, ".xtpkg-setup"), operationMarker)
    local state, plan, pathApplied
    local ok, err = pcall(function()
        ownedApp(path.join(prefix, "app")); Launchers.verify(path.join(prefix, "bin"))
        if not options.noPath then Launchers.pathConflict("xtpkg", path.join(prefix, "bin")) end
        local runtime = Launchers.runtime()
        if process.exec("git", { "--version" }).code ~= 0 then error("Git is required on PATH", 0) end
        local app = path.join(work, "app"); fs.mkdir(app, false):await()
        Util.noLinksTree(path.join(source, "src"))
        fs.copy(path.join(source, "src"), path.join(app, "src"), true):await()
        for _, name in ipairs({ "xtpkg.toml", "xtpkg.lock", "README.md", "LICENSE", "install.sh", "install.cmd" }) do
            local from = path.join(source, name); Util.noLinks(from)
            if fs.exists(from) then fs.copy(from, path.join(app, name)):await() end
        end
        Util.mkdir(path.join(app, "tools"))
        for _, name in ipairs({ "install-windows.ps1", "validate-registry.luau" }) do
            local from = path.join(source, "tools", name); Util.noLinks(from)
            if fs.exists(from) then fs.copy(from, path.join(app, "tools", name)):await() end
        end
        local manifest = Manifest.load(app)
        if not fs.exists(path.join(app, manifest.package.entry)) then error("XTPKG entrypoint is missing", 0) end
        if next(manifest.dependencies) ~= nil then
            for name, spec in pairs(manifest.dependencies) do if Util.pathSpec(spec) then manifest.dependencies[name] = "path:" .. Util.localPath(source, spec) end end
            Manifest.save(app, manifest)
            local r = process.exec(runtime, { path.join(app, "src", "main.luau"), "install" }, { cwd = app })
            if r.code ~= 0 then error("Dependency bootstrap failed; existing installation is unchanged.\n" .. r.stdout .. r.stderr, 0) end
        end
        fs.writeSync(path.join(app, ".xtpkg-app"), appMarker)
        Launchers.write(path.join(work, "bin"), { xtpkg = path.join(prefix, "app", "src", "bootstrap.luau") }, runtime)
        -- Check the staged CLI before changing any installed files or PATH.
        local probe = process.exec(runtime, { path.join(app, manifest.package.entry), "--version" }, { cwd = app })
        if probe.code ~= 0 then error("Staged XTPKG failed its startup check", 0) end
        plan = PathSetup.plan({ path.join(prefix, "bin"), path.join(Config.global(), "bin") }, options.noPath)
        state = { version = 1, app = fs.exists(path.join(prefix, "app")), bin = fs.exists(path.join(prefix, "bin")), committed = false }
        journal(work, state)
        for _, name in ipairs({ "app", "bin" }) do
            local target = path.join(prefix, name)
            if fs.exists(target) then fs.rename(target, path.join(work, "old-" .. name)):await() end
            fs.rename(path.join(work, name), target):await()
        end
        plan.apply(); pathApplied = true
        state.committed = true; journal(work, state)
    end)
    if not ok then
        local restored, detail = pcall(function()
            if pathApplied then plan.undo() end
            if state then state.committed = false; restore(prefix, work, state) end
        end)
        if not restored then error(tostring(err) .. "\nRollback needs manual recovery; preserve " .. work .. ": " .. tostring(detail), 0) end
    end
    Util.noLinksTree(work); Util.remove(work)
    if not ok then error(err, 0) end
    print("Installed XTPKG in " .. path.join(prefix, "app") .. "\nExecutable directory: " .. path.join(prefix, "bin"))
    if options.noPath then print("PATH was not changed (--no-path). Add the executable directory and global bin directory yourself.")
    else print("User PATH configured. Open a new terminal (or reload your shell profile) to run xtpkg from any directory.") end
    return prefix
end
return Install
