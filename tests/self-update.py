"""Self-updates use real local Git snapshots under official-source cache keys.
No public downloads, live installation writes, or package install hooks run.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
from support import Harness, ROOT, luau_string

with tempfile.TemporaryDirectory(prefix="xtpkg-self-tests-") as temporary:
    h = Harness(temporary)
    prefix = h.base / "host"
    registry = h.base / "registry"
    registry.mkdir()
    h.env["XTPKG_REGISTRY"] = str(registry)
    h.run([h.runtime, ROOT / "src/setup/main.luau", "--prefix", prefix, "--no-path"])
    executable = prefix / "bin" / ("xtpkg.cmd" if os.name == "nt" else "xtpkg")
    h.env["PATH"] = str(prefix / "bin") + os.pathsep + h.env["PATH"]
    root = Path(h.env["XTPKG_GLOBAL_DIR"])
    source = h.base / "package"
    source.mkdir()
    (source / "src").mkdir()
    h.run(["git", "init", "-q"], cwd=source)
    h.run(["git", "config", "user.name", "Fixture"], cwd=source)
    h.run(["git", "config", "user.email", "fixture@example.invalid"], cwd=source)
    h.run(["git", "config", "core.autocrlf", "false"], cwd=source)
    manifest = '[package]\nname="xtpkg"\nversion="VERSION"\nentry="src/main.luau"\nrepository="https://github.com/MINTILER-DEV/xtpkg"\n[dependencies]\n[bin]\nxtpkg="src/main.luau"\n'
    metadata = {"name": "xtpkg", "description": "Self update fixture", "repository": "https://github.com/MINTILER-DEV/xtpkg", "versions": {}}
    for version in ("0.2.1", "0.2.2"):
        if version == "0.2.1":
            (source / "src/main.luau").write_text('''local fs=require("system/fs")
fs.writeSync("legacy-ran","yes")
for _,a in ipairs({...}) do if a=="-g" or a=="--global" then error("Legacy globals must use the host",0) end end
print("LEGACY_CLI")
''', encoding="utf-8", newline="")
        else:
            shutil.copytree(ROOT / "src", source / "src", dirs_exist_ok=True)
        (source / "xtpkg.toml").write_text(manifest.replace("VERSION", version), encoding="utf-8", newline="")
        h.run(["git", "add", "."], cwd=source)
        h.run(["git", "commit", "-qm", version], cwd=source)
        revision = h.run(["git", "rev-parse", "HEAD"], cwd=source).strip()
        prepare = h.base / "cache.luau"
        prepare.write_text('''local S=require(%s)
local C=require(%s)
local snapshot=S.gitSnapshot(%s,%s,C.root(true),true)
local package={name="xtpkg",version=%s,source="git+https://github.com/MINTILER-DEV/xtpkg",revision=%s}
C.write("packages",C.packageKey(package),snapshot)
print(snapshot.integrity)
''' % tuple(luau_string(v) for v in ((ROOT / "src/package/Source").as_posix(), (ROOT / "src/package/Cache").as_posix(), source.as_posix(), revision, version, revision)), encoding="utf-8")
        integrity = h.run([h.runtime, prepare]).strip()
        metadata["versions"][version] = {"source": {"type": "git", "url": metadata["repository"], "revision": revision}, "integrity": integrity, "entry": "src/main.luau", "dependencies": {}}
    (registry / "packages").mkdir()
    (registry / "packages/xtpkg.json").write_text(json.dumps(metadata), encoding="utf-8")
    (registry / "index.json").write_text(json.dumps({"registry_version": 1, "packages": {"xtpkg": {"path": "packages/xtpkg.json"}}}), encoding="utf-8")
    h.launch(executable, ["add", "xtpkg@0.2.1", "-g"])
    h.check(not (h.cwd / "legacy-ran").exists(), "Installation must not execute downloaded code")
    h.check(h.launch(executable, ["--version"]).strip() == "xtpkg 0.2.1")
    h.check(not (h.cwd / "legacy-ran").exists())
    h.check("LEGACY_CLI" in h.launch(executable, ["help"]))
    h.check("xtpkg" in h.launch(executable, ["list", "-g"]))
    h.launch(executable, ["-q", "config", "set", "registry", str(registry)])
    config = h.base / "config/xtpkg/config.json"
    h.check(config.read_text().startswith('{\n  "registry": '))
    h.check(json.loads(config.read_text())["registry"] == registry.as_posix())
    h.launch(executable, ["install", "-g", "--frozen"])
    h.check(h.launch(executable, ["version"]).strip() == "xtpkg 0.2.1")
    original_lock = (root / "xtpkg.lock").read_bytes()
    original_manifest = (root / "xtpkg.toml").read_bytes()
    (root / "xtpkg.lock").write_text("broken lock\n", encoding="utf-8")
    h.check("xtpkg 0.2.2" in h.launch(executable, ["--version"]))
    (root / "xtpkg.lock").write_bytes(original_lock)
    h.check(h.launch(executable, ["-q", "--version"]).strip() == "xtpkg 0.2.1")
    rollback = h.base / "rollback.luau"
    rollback.write_text('''local O=require(%s)
local fs=require("system/fs")
local P=require("async/promise")
local rename=fs.rename
local injected=false
fs.rename=function(a,b)
 if not injected and b:sub(-10)=="xtpkg.toml" and a:find(".xtpkg-stage-",1,true) then injected=true; return P.reject("self rollback") end
 return rename(a,b)
end
local ok=pcall(function() O.perform({global=true},function(m) m.dependencies.xtpkg="0.2.2" end) end)
assert(injected and not ok)
print("ROLLBACK_OK")
''' % luau_string((ROOT / "src/package/Operations").as_posix()), encoding="utf-8")
    h.check("ROLLBACK_OK" in h.run([h.runtime, rollback], cwd=root, env=dict(h.env, XTPKG_HOST_ROOT=str(prefix / "app"))))
    h.check((root / "xtpkg.lock").read_bytes() == original_lock)
    h.check((root / "xtpkg.toml").read_bytes() == original_manifest)
    h.check(h.launch(executable, ["version"]).strip() == "xtpkg 0.2.1")
    h.launch(executable, ["add", "xtpkg@0.2.2", "-g"])
    h.check(h.launch(executable, ["--version"]).strip() == "xtpkg 0.2.2")
    h.check("xtpkg" in h.launch(executable, ["list", "-g"]))
    h.launch(executable, ["update", "xtpkg", "-g"])
    spoof = h.package("spoof", {"xtpkg": "cli.luau"})
    h.check("official registry package" in h.cli("add", str(spoof), "-g", ok=False))
    h.launch(executable, ["remove", "xtpkg", "-g"])
    h.check(h.launch(executable, ["--version"]).strip() == "xtpkg 0.2.2")
    h.check(not (root / "packages/xtpkg").exists())
    h.check(not list(root.glob(".xtpkg-stage-*")))
    print(f"PASS: {h.count} self-update integration assertions")
