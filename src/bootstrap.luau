-- Stable installed command: dispatch to a verified global XTPKG selection.
-- Legacy releases keep global operations on the host so downgrading to 0.2.1
-- cannot reintroduce its reserved-name failure and strand the updater.
local path = require("system/path")
local SelfUpdate = require("./package/SelfUpdate")
local Launchers = require("./package/Launchers")
local root = path.dirname(path.dirname(process.argv[2]))
local incoming = { ... }
local ok, err = pcall(function()
    local selection = SelfUpdate.selection()
    if selection and (#incoming == 1 and (incoming[1] == "--version" or incoming[1] == "version")) then print("xtpkg " .. selection.version); return end
    local global = false
    for _, argument in ipairs(incoming) do
        if argument == "--" then break end
        if argument == "--global" or (argument:sub(1, 2) ~= "--" and argument:match("^%-[a-z]*g[a-z]*$")) then global = true end
    end
    local entry = selection and (selection.modern or not global) and selection.entry or path.join(root, "src", "main.luau")
    local arguments = { entry }; for _, argument in ipairs(incoming) do table.insert(arguments, argument) end
    local result = process.exec(Launchers.runtime(), arguments, { cwd = process.cwd(), env = { XTPKG_HOST_ROOT = root } })
    if result.stdout ~= "" then print((result.stdout:gsub("\r?\n$", ""))) end
    if result.stderr ~= "" then print((result.stderr:gsub("\r?\n$", ""))) end
    if result.code ~= 0 then process.exit(result.code) end
end)
if not ok then print("error: " .. tostring(err):gsub("\nstack traceback:.*", "")); process.exit(1) end
