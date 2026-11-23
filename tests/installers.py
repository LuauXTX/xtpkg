import json
import os
from pathlib import Path
import shutil
import tempfile
from support import Harness, ROOT

with tempfile.TemporaryDirectory(prefix="xtpkg-install-tests-") as temporary:
    h = Harness(temporary)
    prefix = h.base / "install with spaces"
    profile = h.base / "shell profile"
    h.env["XTPKG_PATH_PROFILE"] = str(profile)
    extension = ".cmd" if os.name == "nt" else ""

    def install(*args, ok=True, env=None):
        environment = env or h.env
        if os.name == "nt":
            command = '"' + str(ROOT / "install.cmd") + '" ' + " ".join('"' + str(a) + '"' for a in ("--prefix", prefix, *args))
            import subprocess
            return h.run(subprocess.list2cmdline([os.environ["COMSPEC"]]) + ' /d /v:off /s /c "' + command + '"', ok=ok, env=environment)
        return h.run(["sh", ROOT / "install.sh", "--prefix", prefix, *args], ok=ok, env=environment)

    # A pre-existing profile is preserved, and repeated installation is idempotent.
    profile.write_text("# keep my settings\nexport KEEP_THIS=yes\n", encoding="utf-8")
    if os.name != "nt": profile.chmod(0o600)
    h.check("Installed XTPKG" in install())
    executable = prefix / "bin" / ("xtpkg" + extension)
    h.check("xtpkg " in h.launch(executable, ["--version"]))
    h.check("Usage:" in h.launch(executable, ["help", "add"]))
    content = profile.read_text()
    h.check(content.startswith("# keep my settings\nexport KEEP_THIS=yes\n"))
    h.check(content.count("# >>> xtpkg PATH >>>") == 1)
    if os.name != "nt": h.check(profile.stat().st_mode & 0o777 == 0o600)
    h.check((prefix / "app/src/main.luau").exists())
    sentinel = h.base / "config/xtpkg/config.json"
    sentinel.parent.mkdir(parents=True, exist_ok=True)
    sentinel.write_text('{"registry":"https://example.invalid/registry"}')
    cache = h.base / "cache/sentinel.txt"
    cache.parent.mkdir(parents=True, exist_ok=True)
    (cache.parent / ".xtpkg-cache").write_bytes(b"xtpkg-cache-v1\n")
    cache.write_text("keep cache")
    install()
    h.check(profile.read_text() == content)
    h.check(sentinel.read_text() == '{"registry":"https://example.invalid/registry"}')
    h.check(cache.read_text() == "keep cache")
    # Verify exact arguments through the installed launcher, including empty and
    # quoted shell metacharacters, by temporarily substituting a trusted probe.
    main = prefix / "app/src/main.luau"
    main_before = main.read_bytes()
    main.write_text('local j=require("serde/json"); local a={}; for i=3,#process.argv do table.insert(a,process.argv[i]) end; print(j.encode(a))\n', encoding="utf-8")
    arguments = ["a b", "", "^1.2.3", "a&b", "a|b", "x>y", "é"]
    h.check(json.loads(h.launch(executable, arguments)) == arguments)
    main.write_bytes(main_before)

    # Failure after the app and bin replacements must restore both and PATH.
    injected = h.base / "inject.luau"
    injected.write_text('''local I=require(%s)
local fs=require("system/fs")
local original=fs.rename
local injected=false
fs.rename=function(a,b)
 if not injected and b==%s and a:find(".xtpkg-",1,true) then injected=true; error("profile failure",0) end
 return original(a,b)
end
local ok,err=pcall(function() I.run(%s,{prefix=%s}) end)
assert(injected and not ok and tostring(err):find("profile failure",1,true))
print("ROLLBACK_OK")
''' % tuple(json.dumps(str(p).replace("\\", "/")) for p in (ROOT / "src/setup/Install", profile, ROOT, prefix)), encoding="utf-8")
    # Make a different PATH block so the atomic profile-write failure is reached.
    profile.write_text("# changed safely before setup\n", encoding="utf-8")
    h.check("ROLLBACK_OK" in h.run([h.runtime, injected]))
    h.check(main.read_bytes() == main_before)
    h.check(profile.read_text() == "# changed safely before setup\n")
    h.check("xtpkg " in h.launch(executable, ["--version"]))
    h.check(not (prefix / ".xtpkg-setup-operation").exists())

    # Abrupt termination leaves backups and a journal; default setup will not
    # steal the guard. Explicit --recover restores before reinstalling.
    interrupted = h.base / "interrupt.luau"
    interrupted.write_text('''local I=require(%s)
local fs=require("system/fs")
local original=fs.rename
fs.rename=function(a,b)
 if b==%s and a:find(".xtpkg-setup-operation/bin",1,true) then process.exit(77) end
 return original(a,b)
end
I.run(%s,{prefix=%s,noPath=true})
''' % tuple(json.dumps(str(p).replace("\\", "/")) for p in (ROOT / "src/setup/Install", prefix / "bin", ROOT, prefix)), encoding="utf-8")
    h.run([h.runtime, interrupted], ok=False)
    h.check((prefix / ".xtpkg-setup-operation/journal.json").exists())
    h.check("--recover" in install(ok=False))
    install("--recover")
    h.check("xtpkg " in h.launch(executable, ["--version"]))
    h.check(not (prefix / ".xtpkg-setup-operation").exists())

    # Managed launchers are never overwritten when a user has modified them.
    launcher_bytes = executable.read_bytes()
    executable.write_text("user executable", encoding="utf-8")
    h.check("modified executable" in install(ok=False))
    h.check(executable.read_text() == "user executable")
    executable.write_bytes(launcher_bytes)
    install("--no-path")

    # Source dependencies are bootstrapped through the regular package manager;
    # the explicit script hook below must never execute.
    source = h.base / "source"
    shutil.copytree(ROOT / "src", source / "src")
    dependency = h.package("setup-library")
    manifest = (ROOT / "xtpkg.toml").read_text().replace("[dependencies]", '[dependencies]\n"setup-library" = "path:' + dependency.as_posix() + '"')
    (source / "xtpkg.toml").write_text(manifest + '\n[hooks]\ninstall="echo UNSAFE_HOOK"\n', encoding="utf-8")
    bootstrap = h.base / "bootstrap.luau"
    bootstrap.write_text('local I=require(' + json.dumps((ROOT / "src/setup/Install").as_posix()) + '); I.run(' + json.dumps(source.as_posix()) + ',{prefix=' + json.dumps(prefix.as_posix()) + ',noPath=true})', encoding="utf-8")
    output = h.run([h.runtime, bootstrap])
    h.check("UNSAFE_HOOK" not in output)
    h.check((prefix / "app/packages/setup-library/init.luau").exists())
    h.check((prefix / "app/xtpkg.lock").exists())
    h.check(sentinel.exists() and cache.exists())
    print(f"PASS: {h.count} native installer assertions ({os.name})")
