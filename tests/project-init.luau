local P = require("../src/package/ProjectInit")
local A = require("../src/cli/args")
local count = 0
local function check(value) count += 1; assert(value, "project init check " .. count) end
local function lines(text, expected)
    local found = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do if line:gsub("\r$", "") == expected then found += 1 end end
    return found
end
local append, added = P.ignoreAppend("")
check(added == #P.ignoreEntries)
for _, entry in ipairs(P.ignoreEntries) do check(lines(append, entry) == 1) end
check(P.ignoreAppend(append) == "")
check(append:find("!/xtpkg.lock", 1, true) ~= nil)
check(lines(append, "xtpkg.lock") == 0 and lines(append, "*.lock") == 0)
local original = "# retain this\r\n.env\r\npackages/\r\ncustom ignored file"
local delta = P.ignoreAppend(original)
check(delta:sub(1, 2) == "\r\n")
check(lines(delta, ".env") == 0 and lines(delta, "/packages/") == 0)
check(not delta:gsub("\r\n", ""):find("\n", 1, true))
check(P.ignoreAppend(original .. delta) == "")
check(P.ignoreAppend("\239\187\191.env\n"):find("\n.env\n", 1, true) == nil)
check(lines(P.ignoreAppend(".env   \n"), ".env") == 0)
local parsed = A.parse({ "init", "--no-git", "--no-gitignore" })
check(parsed["no-git"] and parsed["no-gitignore"])
print("Project initialization checks passed: " .. count)
