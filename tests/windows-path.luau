-- Exercise the real Windows registry backend in a fresh disposable HKCU key.
-- Calls for the actual Environment key are redirected before the helper runs.
local P = require("../src/setup/PathSetup")
local base64 = require("crypto/base64")
local key = ({ ... })[1]
assert(type(key) == "string" and key:match("^Software\\XTPKGTests%-[A-Za-z0-9_-]+$"))
local originalExec, originalGetenv = process.exec, process.getenv
local seed = "C:\\keep;C:\\donné;%USERPROFILE%\\bin"
local function read(location)
    local r = originalExec("powershell.exe", { "-NoProfile", "-NonInteractive", "-Command", "$k=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($env:XTPKG_PATH_KEY); $v=''; if($k) { $v=[string]$k.GetValue('Path','',[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)+'|'+$k.GetValueKind('Path').ToString(); $k.Dispose() }; [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($v))" }, { env = { XTPKG_PATH_KEY = location } })
    assert(r.code == 0); return base64.decode(r.stdout:match("^%s*(.-)%s*$"))
end
local realBefore = read("Environment")
local r = originalExec("powershell.exe", { "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference='Stop'; if([Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($env:XTPKG_PATH_KEY)) { throw 'Test key already exists' }; $k=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($env:XTPKG_PATH_KEY); $k.SetValue('Path',$env:XTPKG_PATH_SEED,[Microsoft.Win32.RegistryValueKind]::ExpandString); $k.Dispose()" }, { env = { XTPKG_PATH_KEY = key, XTPKG_PATH_SEED = seed } })
assert(r.code == 0)
process.getenv = function(name) if name == "XTPKG_PATH_PROFILE" then return nil end; return originalGetenv(name) end
process.exec = function(command, arguments, options)
    if command == "powershell.exe" then
        arguments = table.clone(arguments)
        for i, a in ipairs(arguments) do
            if a:find("SendMessageTimeout", 1, true) then return { code = 0, stdout = "", stderr = "" } end
            arguments[i] = a:gsub("'Environment'", function() return "'" .. key .. "'" end)
        end
    end
    return originalExec(command, arguments, options)
end
local ok, err = pcall(function()
    local directories = { "C:/XTPKG test é/bin", "C:/XTPKG test é/global/bin" }
    local plan = P.plan(directories)
    plan.apply()
    local after = read(key)
    assert(after == seed .. ";" .. table.concat(directories, ";") .. "|ExpandString", "PATH contents/type were not preserved")
    local again = P.plan(directories); again.apply(); assert(read(key) == after); again.undo()
    plan.undo(); assert(read(key) == seed .. "|ExpandString", "PATH rollback failed")
    assert(read("Environment") == realBefore, "Real user PATH changed")
end)
process.exec, process.getenv = originalExec, originalGetenv
local clean = originalExec("powershell.exe", { "-NoProfile", "-NonInteractive", "-Command", "[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($env:XTPKG_PATH_KEY,$false)" }, { env = { XTPKG_PATH_KEY = key } })
assert(clean.code == 0)
assert(ok, tostring(err))
print("REGISTRY_PATH_OK")
