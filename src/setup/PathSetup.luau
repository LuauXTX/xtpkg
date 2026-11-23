local fs = require("system/fs")
local path = require("system/path")
local Util = require("../package/Util")
local Json = require("../package/Json")
local Launchers = require("../package/Launchers")
local base64 = require("crypto/base64")
local PathSetup = {}
local beginMarker, endMarker = "# >>> xtpkg PATH >>>", "# <<< xtpkg PATH <<<"
local function powershell(script, environment)
    environment = table.clone(environment or {})
    -- A PowerShell 7 parent may export incompatible module paths to WinPS 5.1.
    -- Load only the system modules needed for registry JSON and notifications.
    environment.PSModulePath = path.join(assert(process.getenv("SystemRoot")), "System32", "WindowsPowerShell", "v1.0", "Modules")
    return process.exec("powershell.exe", { "-NoProfile", "-NonInteractive", "-Command", script }, { env = environment })
end

function PathSetup.windowsValue(value, directories)
    local result, seen = value, {}
    local function key(s)
        s = s:gsub("%%([^%%]+)%%", function(name) return process.getenv(name) or ("%" .. name .. "%") end)
        return s:gsub('^"(.*)"$', "%1"):gsub("\\", "/"):gsub("/+$", ""):lower()
    end
    -- Preserve unrelated entries and literal %VARIABLE% references.
    for entry in value:gmatch("[^;]+") do
        seen[key(entry)] = true
    end
    for _, dir in ipairs(directories) do
        if not seen[key(dir)] then result ..= (result == "" or result:sub(-1) == ";") and dir or (";" .. dir); seen[key(dir)] = true end
    end
    return result
end

function PathSetup.profile(text, directories, fish)
    local block = { beginMarker }
    for _, dir in ipairs(directories) do
        if dir:find("[%c]") then error("Control character in PATH directory", 0) end
        if fish then
            local quoted = "'" .. dir:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
            table.insert(block, "if not contains -- " .. quoted .. " $PATH; set -gx PATH " .. quoted .. " $PATH; end")
        else
            local quoted = Launchers.shell(dir)
            table.insert(block, 'case ":$PATH:" in *:' .. quoted .. ':*) ;; *) PATH=' .. quoted .. '${PATH:+:"$PATH"} ;; esac')
        end
    end
    if not fish then table.insert(block, "export PATH") end
    table.insert(block, endMarker)
    local newBlock = table.concat(block, "\n")
    local a, b = text:find(beginMarker, 1, true), text:find(endMarker, 1, true)
    if (a and not b) or (b and not a) or (a and (b < a or text:find(beginMarker, a + #beginMarker, true) or text:find(endMarker, b + #endMarker, true))) then error("Malformed/duplicate XTPKG PATH block; repair the profile before reinstalling", 0) end
    if a then return text:sub(1, a - 1) .. newBlock .. text:sub(b + #endMarker) end
    return text .. (#text > 0 and text:sub(-1) ~= "\n" and "\n" or "") .. newBlock .. "\n"
end

local function write(filename, text)
    Util.noLinks(filename); Util.mkdir(path.dirname(filename))
    local temporary = filename .. ".xtpkg-" .. Util.id()
    local ok, err = pcall(function()
        if Launchers.windows() then
            if fs.exists(filename) then
                local r = powershell("$ErrorActionPreference='Stop'; $section=[Security.AccessControl.AccessControlSections]::Access; $original=[IO.File]::GetAccessControl($env:XTPKG_PROFILE_FROM,$section); $acl=[Security.AccessControl.FileSecurity]::new(); $acl.SetSecurityDescriptorSddlForm($original.GetSecurityDescriptorSddlForm($section),$section); $f=[IO.File]::Open($env:XTPKG_PROFILE_TO,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None); $f.Dispose(); [IO.File]::SetAccessControl($env:XTPKG_PROFILE_TO,$acl)", { XTPKG_PROFILE_FROM = filename, XTPKG_PROFILE_TO = temporary })
                if r.code ~= 0 then error("Could not preserve profile permissions: " .. r.stderr .. r.stdout, 0) end
            end
        else
            local mode
            if fs.exists(filename) then
                local r = process.exec("/usr/bin/stat", { "-c", "%a", filename })
                if r.code ~= 0 then r = process.exec("/usr/bin/stat", { "-f", "%Lp", filename }) end
                mode = r.stdout:match("^([0-7]+)%s*$")
                if r.code ~= 0 or not mode then error("Could not read profile permissions", 0) end
            end
            local r = process.exec("/bin/sh", { "-c", 'umask 077; set -C; : > "$1"', "sh", temporary })
            if r.code ~= 0 then error("Could not create private profile staging file", 0) end
            -- Write under mode 0600 before restoring any original access mode.
            fs.writeSync(temporary, text)
            if mode and process.exec("/bin/chmod", { mode, temporary }).code ~= 0 then error("Could not preserve profile permissions", 0) end
        end
        if Launchers.windows() then fs.writeSync(temporary, text) end
        fs.rename(temporary, filename):await()
    end)
    if not ok then Util.remove(temporary); error(err, 0) end
end

local function registryRead()
    local r = powershell("$ErrorActionPreference='Stop'; $k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment'); $v=''; $kind='ExpandString'; $exists=$false; if($k) { if($k.GetValueNames() -contains 'Path') { $exists=$true; $v=$k.GetValue('Path','',[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); $kind=$k.GetValueKind('Path').ToString() }; $k.Dispose() }; $j=@{value=$v; kind=$kind; exists=$exists} | ConvertTo-Json -Compress; [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($j))")
    if r.code ~= 0 then error("Cannot read user PATH from the registry", 0) end
    local state = Json.decode(base64.decode(r.stdout:match("^%s*(.-)%s*$")), 65536)
    if type(state.value) ~= "string" or (state.kind ~= "String" and state.kind ~= "ExpandString") then error("Unsupported user PATH registry value", 0) end
    return state
end
local function registryWrite(state)
    local r = powershell("$ErrorActionPreference='Stop'; $s=$env:XTPKG_PATH_STATE | ConvertFrom-Json; $k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment'); try { if($s.exists) { $kind=[Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$s.kind); $k.SetValue('Path',[string]$s.value,$kind) } else { $k.DeleteValue('Path',$false) } } finally { $k.Dispose() }", { XTPKG_PATH_STATE = Json.encode(state) })
    if r.code ~= 0 then error("Cannot update user PATH registry value", 0) end
end
local function notifyWindows()
    -- Notify Explorer/new terminals without modifying any unrelated variables.
    local r = powershell("Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class XtpkgEnvironmentNotice { [DllImport(\"user32.dll\", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, UIntPtr wp, string lp, uint flags, uint timeout, out UIntPtr result); }'; $r=[UIntPtr]::Zero; [void][XtpkgEnvironmentNotice]::SendMessageTimeout([IntPtr]65535,26,[UIntPtr]::Zero,'Environment',2,2000,[ref]$r)")
    if r.code ~= 0 then print("PATH updated; sign out and back in if new terminals do not see it.") end
end

function PathSetup.plan(directories, disabled)
    for _, dir in ipairs(directories) do
        if dir:find("%c") or (Launchers.windows() and dir:find(";", 1, true)) or (not Launchers.windows() and dir:find(":", 1, true)) then error("Install/global directory cannot contain a PATH separator or control character", 0) end
    end
    local edits, applied = {}, {}
    local plan = {}
    local windows = Launchers.windows() and not process.getenv("XTPKG_PATH_PROFILE")
    local before, after
    if not disabled then
        if windows then
            before = registryRead(); after = { value = PathSetup.windowsValue(before.value, directories), kind = before.kind, exists = true }
        else
            local home = assert(process.getenv("HOME") or process.getenv("USERPROFILE"), "HOME/USERPROFILE is required for PATH setup")
            local profiles = {}
            local override = process.getenv("XTPKG_PATH_PROFILE")
            if override then table.insert(profiles, { name = Util.absolute(process.cwd(), override) })
            else
                table.insert(profiles, { name = path.join(home, ".profile") })
                table.insert(profiles, { name = path.join(home, ".bashrc") })
                if fs.exists(path.join(home, ".bash_profile")) then table.insert(profiles, { name = path.join(home, ".bash_profile") }) end
                local shell = process.getenv("SHELL") or ""
                for _, name in ipairs({ ".zprofile", ".zshrc" }) do
                    if shell:match("zsh$") or fs.exists(path.join(home, name)) then table.insert(profiles, { name = path.join(home, name) }) end
                end
                if shell:match("fish$") then table.insert(profiles, { name = path.join(process.getenv("XDG_CONFIG_HOME") or path.join(home, ".config"), "fish", "conf.d", "xtpkg.fish"), fish = true }) end
            end
            for _, profile in ipairs(profiles) do
                Util.noLinks(profile.name)
                if fs.exists(profile.name) and (not fs.stat(profile.name):await().isFile or fs.stat(profile.name):await().size > 1024 * 1024) then error("Unsupported/oversized shell profile: " .. profile.name, 0) end
                local text = fs.exists(profile.name) and fs.readSync(profile.name) or nil
                table.insert(edits, { name = profile.name, before = text, after = PathSetup.profile(text or "", directories, profile.fish) })
            end
        end
    end
    function plan.undo()
        if windows and #applied > 0 then
            local current = registryRead()
            if current.value ~= after.value or current.kind ~= after.kind then error("User PATH changed concurrently; restore it manually", 0) end
            registryWrite(before); table.clear(applied)
        else
            for i = #applied, 1, -1 do
                local e = applied[i]
                Util.noLinks(e.name)
                if not fs.exists(e.name) or fs.readSync(e.name) ~= e.after then error("Shell profile changed concurrently; restore PATH manually: " .. e.name, 0) end
                if e.before == nil then fs.remove(e.name):await() else write(e.name, e.before) end
                table.remove(applied, i)
            end
        end
    end
    function plan.apply()
        if disabled then return end
        local ok, err = pcall(function()
            if windows then
                local current = registryRead()
                if Json.encode(current) ~= Json.encode(before) then error("User PATH changed concurrently; retry installation", 0) end
                if before.value ~= after.value or not before.exists then registryWrite(after); table.insert(applied, true); notifyWindows() end
            else
                for _, e in ipairs(edits) do
                    Util.noLinks(e.name)
                    local current = fs.exists(e.name) and fs.readSync(e.name) or nil
                    if current ~= e.before then error("Shell profile changed concurrently; retry installation: " .. e.name, 0) end
                    if e.before ~= e.after then write(e.name, e.after); table.insert(applied, e) end
                end
            end
        end)
        if not ok then plan.undo(); error(err, 0) end
    end
    return plan
end
return PathSetup
