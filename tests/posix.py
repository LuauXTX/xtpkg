"""POSIX shell/launcher tests; also runnable under Git Bash on Windows.

Native filesystem/runtime integration runs in global.py and installers.py on
each CI OS. Here the runtime is a recorder so shell quoting is tested directly.
"""
import os
from pathlib import Path
import shutil
import shlex
import tempfile
from support import Harness, ROOT

shell = shutil.which("sh")
if os.name == "nt":
    shell = str(Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/bin/sh.exe")
if not shell or not Path(shell).exists():
    raise SystemExit("A POSIX shell (or Git Bash on Windows) is required")

with tempfile.TemporaryDirectory(prefix="xtpkg-shell-tests-") as temporary:
    h = Harness(temporary)
    fake = h.base / "fake tools"
    fake.mkdir()
    record = h.base / "argv.bin"
    recorder = fake / "runtime"
    recorder.write_text('#!/bin/sh\nprintf "%s\\0" "$@" > "$RECORD_FILE"\n', encoding="utf-8")
    (fake / "uname").write_text('#!/bin/sh\nprintf "%s\\n" "${TEST_OS:-Linux}"\n', encoding="utf-8")
    (fake / "git").write_text('#!/bin/sh\nexit 0\n', encoding="utf-8")
    h.run([shell, "-c", 'chmod +x "$1"/*', "sh", fake.as_posix()])
    env = dict(h.env, LUAUXTX_BIN=recorder.as_posix(), RECORD_FILE=record.as_posix(), TEST_OS="Linux")
    # Prefix PATH inside sh to use the POSIX separator even when hosted on Windows.
    def frontend(arguments, *, ok=True, environment=env):
        driver = h.base / "frontend-test.sh"
        driver.write_text('extra=' + shlex.quote(fake.as_posix()) + '\ncase "$extra" in [A-Za-z]:/*) extra=$(cygpath -u "$extra");; esac\nPATH="$extra:$PATH"; export PATH\nexec sh ' + shlex.quote((ROOT / "install.sh").as_posix()) + ' ' + ' '.join(shlex.quote(a) for a in arguments) + '\n', encoding="utf-8")
        return h.run([shell, driver.as_posix()], ok=ok, env=environment)

    arguments = ["--prefix", "/a path/quo'te", "", "^1.0.0", "a&b", "a|b", 'a"b', "100%", "é"]
    frontend(arguments)
    captured = record.read_bytes().decode("utf-8").split("\0")[:-1]
    h.check(captured[0].replace("\\", "/").endswith("/src/setup/main.luau"), str(captured))
    h.check(captured[1:] == arguments, repr(captured))
    frontend(["--help"], environment=dict(env, TEST_OS="Darwin"))
    h.check("supports Linux and macOS" in frontend([], environment=dict(env, TEST_OS="Unsupported"), ok=False))
    h.check("LuauXTX is required" in frontend([], environment=dict(env, LUAUXTX_BIN="xtpkg-runtime-does-not-exist"), ok=False))

    # Generate the actual POSIX launcher with the production Luau writer.
    launcher = h.base / "launcher with spaces"
    import json
    generator = h.base / "generate.luau"
    generator.write_text('local L=require(' + json.dumps((ROOT / "src/package/Launchers").as_posix()) + '); local fs=require("system/fs"); fs.writeSync(' + json.dumps(launcher.as_posix()) + ',L.render(' + json.dumps(recorder.as_posix()) + ',"/entry path/quo\'te.luau",false))', encoding="utf-8")
    h.run([h.runtime, generator])
    driver = h.base / "launcher-test.sh"
    driver.write_text('chmod +x ' + shlex.quote(launcher.as_posix()) + '\nexec ' + shlex.quote(launcher.as_posix()) + ' ' + ' '.join(shlex.quote(a) for a in arguments) + '\n', encoding="utf-8")
    h.run([shell, driver.as_posix()], env=env)
    captured = record.read_bytes().decode("utf-8").split("\0")[:-1]
    h.check(captured == ["/entry path/quo'te.luau", *arguments], str(captured))

    profile = h.base / "profile"
    profile_generator = h.base / "profile.luau"
    profile_generator.write_text('local P=require(' + json.dumps((ROOT / "src/setup/PathSetup").as_posix()) + '); require("system/fs").writeSync(' + json.dumps(profile.as_posix()) + ',P.profile("", {"/opt/a b/bin", "/opt/quo\'te/bin"}))', encoding="utf-8")
    h.run([h.runtime, profile_generator])
    output = h.run([shell, "-c", 'PATH=/usr/bin:/bin; . "$1"; first=$PATH; . "$1"; [ "$first" = "$PATH" ] || exit 9; printf "%s" "$PATH"', "sh", profile.as_posix()])
    h.check(output.startswith("/opt/quo'te/bin:/opt/a b/bin:"), output)
    print(f"PASS: {h.count} POSIX frontend/launcher assertions")
