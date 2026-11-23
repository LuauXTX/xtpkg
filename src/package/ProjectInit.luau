local fs = require("system/fs")
local path = require("system/path")
local Util = require("./Util")
local ProjectInit = {}

ProjectInit.ignoreEntries = {
    "/packages/", ".xtpkg-*", "*-submission.json", ".env", ".env.*",
    ".DS_Store", "Thumbs.db", "Desktop.ini", ".idea/", ".vscode/",
    "*.swp", "*.swo", "*~", "!/xtpkg.lock",
}

function ProjectInit.ignoreAppend(text)
    local seen = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("\r$", ""):gsub("^\239\187\191", "")
        -- Git ignores unescaped trailing whitespace. Never change the original.
        line = line:gsub("%s+$", "")
        seen[line] = true
    end
    local missing = {}
    for _, entry in ipairs(ProjectInit.ignoreEntries) do
        local covered = seen[entry]
        if entry == "/packages/" then covered = covered or seen["packages/"] or seen["packages"] end
        if not covered then table.insert(missing, entry) end
    end
    if #missing == 0 then return "", 0 end
    local newline = text:find("\r\n", 1, true) and "\r\n" or "\n"
    local separator = text ~= "" and text:sub(-1) ~= "\n" and newline or ""
    return separator .. table.concat(missing, newline) .. newline, #missing
end

function ProjectInit.prepareIgnore(directory)
    local filename = path.join(directory, ".gitignore"); Util.noLinks(filename)
    local existing = fs.exists(filename)
    if existing then
        local info = fs.stat(filename):await()
        if not info.isFile or info.size > 1024 * 1024 then error(".gitignore must be a UTF-8 file no larger than 1 MiB", 0) end
    end
    local original = existing and fs.readSync(filename) or ""
    local append, count = ProjectInit.ignoreAppend(original)
    return function()
        if count == 0 then return 0 end
        Util.noLinks(filename)
        if fs.exists(filename) ~= existing or (existing and fs.readSync(filename) ~= original) then error(".gitignore changed during initialization; retry with --force", 0) end
        -- Append instead of replacing: existing bytes, permissions, and ACLs
        -- remain intact, including a file without a final newline.
        local r
        local environment = { XTPKG_IGNORE_PATH = filename, XTPKG_IGNORE_APPEND = append }
        if process.getenv("COMSPEC") then
            r = process.exec("powershell.exe", { "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference='Stop'; [IO.File]::AppendAllText($env:XTPKG_IGNORE_PATH,$env:XTPKG_IGNORE_APPEND,[Text.UTF8Encoding]::new($false))" }, { env = environment })
        else
            r = process.exec("/bin/sh", { "-c", 'printf "%s" "$XTPKG_IGNORE_APPEND" >> "$XTPKG_IGNORE_PATH"' }, { env = environment })
        end
        if r.code ~= 0 then error("Could not append .gitignore; check file and directory permissions", 0) end
        return count
    end
end

local function metadataAncestor(directory)
    local current = path.normalize(directory)
    while true do
        -- readDir also detects dangling .git links, which exists() may miss.
        local readDirectory = current:match("^%a:$") and current .. "/" or current
        for _, name in ipairs(fs.readDir(readDirectory):await()) do
            if name == ".git" or (process.getenv("COMSPEC") and name:lower() == ".git") then return true end
        end
        -- Bare repositories have no .git child. Treat their metadata conservatively.
        if fs.exists(path.join(current, "HEAD")) and fs.exists(path.join(current, "objects")) and fs.exists(path.join(current, "config")) then return true end
        if current:match("^%a:$") then return false end
        local parent = path.dirname(current)
        if parent == current or parent == "." then return false end
        current = parent
    end
end

function ProjectInit.git(directory, log)
    local checked, exists = pcall(metadataAncestor, directory)
    if not checked then print("warning: Could not check ancestor Git metadata; skipped Git initialization. Run git init manually if appropriate."); return end
    if exists then log("Git metadata exists here or in an ancestor; skipped Git initialization"); return end
    -- Inherited repository overrides must never redirect writes elsewhere.
    for _, variable in ipairs({ "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES" }) do
        local value = process.getenv(variable)
        if value and value ~= "" then print("warning: Git repository environment overrides are set; skipped Git initialization. Run git init manually."); return end
    end
    local options = { cwd = directory, env = { GIT_OPTIONAL_LOCKS = "0", GIT_TERMINAL_PROMPT = "0" } }
    local ok, probe = pcall(process.exec, "git", { "rev-parse", "--git-dir" }, options)
    if not ok then print("warning: Git is unavailable; project files were created. Install Git and run git init manually."); return end
    if probe.code == 0 then log("Using the existing Git repository"); return end
    if probe.code ~= 128 then print("warning: Could not establish Git repository status; skipped Git initialization. Run git init manually if appropriate."); return end
    local initialized, result = pcall(process.exec, "git", { "-c", "core.hooksPath=", "init", "--quiet", "--template=", "." }, options)
    if not initialized or result.code ~= 0 then print("warning: Git initialization failed; project files were created. Check Git configuration/permissions and run git init manually."); return end
    log("Initialized Git repository")
end

return ProjectInit
