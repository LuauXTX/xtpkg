local fs = require("system/fs")
local path = require("system/path")
local Util = require("./Util")
local Json = require("./Json")
local Launchers = {}
local marker = ".xtpkg-bin.json"
function Launchers.windows() return process.getenv("COMSPEC") ~= nil end
function Launchers.shell(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
function Launchers.runtime()
    local executable = process.argv[1]
    if not path.isAbsolute(executable) then
        local r
        if Launchers.windows() then r = process.exec("where.exe", { executable })
        else r = process.exec("sh", { "-c", 'command -v "$1"', "sh", executable }) end
        if r.code ~= 0 then error("Cannot locate the native LuauXTX executable", 0) end
        executable = r.stdout:match("^([^\r\n]+)")
    end
    executable = Util.absolute(process.cwd(), executable)
    if executable:lower():match("%.cmd$") or executable:lower():match("%.bat$") then error("Launchers require the native LuauXTX executable, not a batch wrapper", 0) end
    if not fs.exists(executable) then error("LuauXTX executable is missing: " .. executable, 0) end
    return executable
end
function Launchers.render(runtime, entry, windows)
    if runtime:find('["%c]') or entry:find('["%c]') then error("Unsupported quote/control character in launcher path", 0) end
    if windows then
        local function batch(s) return s:gsub("%%", function() return "%%" end) end
        return '@echo off\r\nsetlocal DisableDelayedExpansion\r\n"' .. batch(runtime) .. '" "' .. batch(entry) .. '" %*\r\nexit /b %errorlevel%\r\n'
    end
    return "#!/bin/sh\nexec " .. Launchers.shell(runtime) .. " " .. Launchers.shell(entry) .. ' "$@"\n'
end
function Launchers.verify(directory)
    Util.noLinksTree(directory)
    if not fs.exists(directory) then return end
    local children = fs.readDir(directory):await()
    if #children == 0 then return end
    local ownership = path.join(directory, marker)
    if not fs.exists(ownership) or fs.stat(ownership):await().size > 65536 then error("Refusing to overwrite an unmanaged bin directory: " .. directory, 0) end
    local data = Json.decode(fs.readSync(ownership), 65536)
    if not Json.object(data) or data.version ~= 1 or not Json.object(data.files) then error("Invalid bin ownership manifest", 0) end
    for _, name in ipairs(children) do
        if name ~= marker then
            local file = path.join(directory, name)
            if not Util.relative(name) or name:find("/", 1, true) or not Util.checksum(data.files[name]) or not fs.stat(file):await().isFile or fs.stat(file):await().size > 65536 or Util.sha(fs.readSync(file)) ~= data.files[name] then error("Unmanaged or modified executable; refusing overwrite/removal: " .. file, 0) end
        end
    end
    for name in pairs(data.files) do if not table.find(children, name) then error("Managed executable is missing; restore it before updating: " .. name, 0) end end
end
function Launchers.conflict(name, destination)
    if name == "xtpkg" then error("Executable name xtpkg is reserved for the package manager", 0) end
    local separator = Launchers.windows() and ";" or ":"
    for dir in (process.getenv("PATH") or ""):gmatch("[^" .. separator .. "]+") do
        dir = dir:gsub('^"(.*)"$', "%1")
        if path.normalize(dir):lower() == path.normalize(destination):lower() then continue end
        for _, suffix in ipairs(Launchers.windows() and { "", ".exe", ".cmd", ".bat", ".com", ".ps1" } or { "" }) do
            if fs.exists(path.join(dir, name .. suffix)) then error("Executable conflict on PATH: " .. name .. " in " .. dir, 0) end
        end
    end
end
function Launchers.write(directory, commands, runtime)
    Util.mkdir(directory)
    local ownership = { version = 1, files = {} }
    for _, name in ipairs(Util.keys(commands)) do
        if not Util.name(name) or name:find("/", 1, true) then error("Unsafe executable name", 0) end
        local filename = name .. (Launchers.windows() and ".cmd" or "")
        local contents = Launchers.render(runtime, commands[name], Launchers.windows())
        local target = path.join(directory, filename)
        fs.writeSync(target, contents)
        if not Launchers.windows() and process.exec("chmod", { "755", target }).code ~= 0 then error("Could not mark launcher executable", 0) end
        ownership.files[filename] = Util.sha(contents)
    end
    fs.writeSync(path.join(directory, marker), Json.encode(ownership))
end
return Launchers
