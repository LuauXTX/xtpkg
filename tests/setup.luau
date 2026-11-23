local Manifest = require("../src/package/Manifest")
local Source = require("../src/package/Source")
local Json = require("../src/package/Json")
local Util = require("../src/package/Util")
local PathSetup = require("../src/setup/PathSetup")
local Launchers = require("../src/package/Launchers")
local Args = require("../src/cli/args")
local count = 0
local function check(v) count += 1; assert(v, "setup check " .. count) end
local function bad(fn) check(not pcall(fn)) end
check(Args.parse({ "add", "foo", "-gq" }).global)
check(Args.parse({ "install", "--global" }).global)
local text = '[package]\nname="a"\nversion="1.0.0"\nentry="main.luau"\n[bin]\nmytool="cli.luau"\n'
check(Manifest.decode(text).bin.mytool == "cli.luau")
for _, line in ipairs({ '../bad="cli.luau"', 'con="cli.luau"', 'mytool="../cli.luau"', 'mytool="native.exe"' }) do bad(function() Manifest.decode(text:gsub('mytool="cli.luau"', function() return line end)) end) end
local files = { ["xtpkg.toml"] = text, ["main.luau"] = "return {}" }
bad(function() Source.validate({files=files,integrity=Util.sha(Json.encode(files))}) end)
files["cli.luau"] = "print('tool')"
check(Source.validate({files=files,integrity=Util.sha(Json.encode(files))}).bin.mytool == "cli.luau")
local windowsPath = 'C:\\Other;C:\\Other;"C:\\Tools\\bin"'
check(PathSetup.windowsValue(windowsPath, { "c:/tools/bin", "C:/New/bin" }) == windowsPath .. ";C:/New/bin")
check(PathSetup.windowsValue("", { "C:/New/bin", "c:/new/bin" }) == "C:/New/bin")
local profile = "# existing settings\nexport KEEP_ME=yes\n"
local updated = PathSetup.profile(profile, { "/home/a b/bin", "/home/quo'te/bin" })
check(updated:sub(1, #profile) == profile)
check(PathSetup.profile(updated, { "/home/a b/bin", "/home/quo'te/bin" }) == updated)
bad(function() PathSetup.profile("# >>> xtpkg PATH >>>\n", { "/a/bin" }) end)
local shell = Launchers.render("/a b/runtime", "/quo'te/main.luau", false)
check(shell:find('"$@"', 1, true) ~= nil)
local cmd = Launchers.render("C:/100%/runtime.exe", "C:/test/main.luau", true)
check(cmd:find("100%%", 1, true) ~= nil and cmd:find("%*", 1, true) ~= nil)
check(cmd:lower():find("call ", 1, true) == nil)
print("Manifest/bin/launcher/PATH checks passed: " .. count)
