import json
import os
from pathlib import Path
import tempfile
from support import Harness, ROOT
from support import luau_string

with tempfile.TemporaryDirectory(prefix="xtpkg-global-tests-") as directory:
    h = Harness(directory)
    h.env["XTPKG_GLOBAL_DIR"] += " é"
    root = Path(h.env["XTPKG_GLOBAL_DIR"])
    extension = ".cmd" if os.name == "nt" else ""
    tool = h.package("tool", {"xtpkg-test-tool": "cli.luau"})
    transitive = h.package("transitive", {"xtpkg-test-transitive": "cli.luau"})
    library = h.package("library", dependencies={"transitive": "path:../transitive"})
    h.check("No dependencies" in h.cli("list", "-g"))
    h.cli("add", "../tool", "--global")
    h.check(not (h.cwd / "xtpkg.toml").exists())
    h.check((root / "packages/tool/cli.luau").is_file())
    executable = root / "bin" / ("xtpkg-test-tool" + extension)
    arguments = ["hello world", "", "^1.2.3", "a&b", "a|b", "x>y", "é", 'say "hello"', "100%", "a!b"]
    h.check(json.loads(h.launch(executable, arguments).strip()) == arguments)
    h.cli("add", str(library), "-g")
    h.check((root / "packages/transitive").is_dir())
    h.check(not (root / "bin" / ("xtpkg-test-transitive" + extension)).exists())
    h.check("library" in h.cli("list", "--global", "--tree"))
    lock = (root / "xtpkg.lock").read_bytes()
    h.cli("install", "-g", "--frozen")
    h.check((root / "xtpkg.lock").read_bytes() == lock)
    (tool / "cli.luau").write_text('print("UPDATED")\n', encoding="utf-8")
    h.cli("update", "tool", "-g")
    h.check("UPDATED" in h.launch(executable, []))
    conflict = h.package("conflict", {"xtpkg-test-tool": "cli.luau"})
    manifest = (root / "xtpkg.toml").read_bytes()
    lock = (root / "xtpkg.lock").read_bytes()
    h.check("Executable conflict" in h.cli("add", str(conflict), "-g", ok=False))
    h.check((root / "xtpkg.toml").read_bytes() == manifest)
    h.check((root / "xtpkg.lock").read_bytes() == lock)
    h.check("UPDATED" in h.launch(executable, []))
    executable.write_text("user changes", encoding="utf-8")
    h.check("modified executable" in h.cli("remove", "tool", "-g", ok=False))
    # Restore using an unmodified managed backup, then verify transactional rollback.
    from hashlib import sha256
    from support import ROOT
    restore = h.base / "restore.luau"
    restore.write_text('local L = require(' + luau_string((ROOT / "src/package/Launchers").as_posix()) + ')\nlocal fs=require("system/fs")\nfs.writeSync(' + luau_string(executable.as_posix()) + ', L.render(' + luau_string(h.runtime.replace("\\", "/")) + ', ' + luau_string((root / "packages/tool/cli.luau").as_posix()) + ', ' + ("true" if os.name == "nt" else "false") + '))\n', encoding="utf-8")
    h.run([h.runtime, restore])
    rollback = h.base / "rollback.luau"
    rollback.write_text('''local fs=require("system/fs")
local Promise=require("async/promise")
local O=require(%s)
local original=fs.rename
local injected=false
fs.rename=function(a,b)
 if not injected and b:sub(-10)=="xtpkg.lock" and a:find(".xtpkg-stage-",1,true) then injected=true; return Promise.reject("global rollback probe") end
 return original(a,b)
end
local ok=pcall(function() O.perform({global=true},nil,true) end)
assert(injected and not ok)
print("ROLLBACK_OK")
''' % json.dumps((ROOT / "src/package/Operations").as_posix()), encoding="utf-8")
    h.check("ROLLBACK_OK" in h.run([h.runtime, rollback], cwd=root))
    h.check((root / "xtpkg.lock").read_bytes() == lock)
    h.check("UPDATED" in h.launch(executable, []))
    h.cli("remove", "tool", "-g", "--offline")
    h.check(not executable.exists())
    h.check((root / "packages/library").is_dir())
    h.cli("remove", "library", "--global")
    h.check("No dependencies" in h.cli("list", "-g"))
    h.check(not list(root.glob(".xtpkg-stage-*")))
    external = h.base / "external-bin"
    external.mkdir()
    (external / ("xtpkg-test-external" + extension)).write_text("unrelated executable")
    outside_tool = h.package("outside-tool", {"xtpkg-test-external": "cli.luau"})
    env = dict(h.env, PATH=str(external) + os.pathsep + h.env["PATH"])
    h.check("conflict on PATH" in h.cli("add", str(outside_tool), "-g", env=env, ok=False))
    h.check((external / ("xtpkg-test-external" + extension)).read_text() == "unrelated executable")
    h.cli("init", "caller")
    h.cli("add", str(tool))
    h.check(not (h.cwd / "bin").exists())
    h.check("not supported" in h.cli("init", "-g", ok=False))
    rename = h.package("rename", {"xtpkg-test-old": "cli.luau"})
    h.cli("add", str(rename), "-g")
    (rename / "xtpkg.toml").write_text((rename / "xtpkg.toml").read_text().replace("xtpkg-test-old", "xtpkg-test-new"), encoding="utf-8")
    h.cli("update", "rename", "-g")
    h.check(not (root / "bin" / ("xtpkg-test-old" + extension)).exists())
    h.check((root / "bin" / ("xtpkg-test-new" + extension)).exists())
    h.cli("remove", "rename", "-g")
    reserved = h.package("reserved", {"git": "cli.luau"})
    h.check("reserved" in h.cli("add", str(reserved), "-g", ok=False))
    print(f"PASS: {h.count} global integration assertions")
