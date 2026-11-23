"""Shared isolated harness for global-package and installer integration tests."""
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def runtime_path(candidate=None):
    runtime = candidate or os.environ.get("LUAUXTX_BIN") or shutil.which("luauxtx")
    if not runtime:
        raise RuntimeError("Install LuauXTX or set LUAUXTX_BIN to its native executable")
    runtime = str(Path(runtime).resolve())
    if Path(runtime).suffix.lower() in (".cmd", ".bat"):
        probe = subprocess.run([runtime, str(ROOT / "tests/runtime-probe.luau")], capture_output=True, text=True, check=True)
        runtime = probe.stdout.strip()
    assert Path(runtime).is_file(), runtime
    return runtime


class Harness:
    def __init__(self, base):
        self.base = Path(base)
        self.runtime = runtime_path()
        self.cwd = self.base / "caller"
        self.cwd.mkdir()
        self.env = dict(os.environ, HOME=str(self.base / "home"),
                        LOCALAPPDATA=str(self.base / "data"), APPDATA=str(self.base / "config"),
                        XDG_DATA_HOME=str(self.base / "data"), XDG_CONFIG_HOME=str(self.base / "config"),
                        XTPKG_CACHE_DIR=str(self.base / "cache"), XTPKG_CONFIG_HOME=str(self.base / "config"),
                        XTPKG_GLOBAL_DIR=str(self.base / "global"), LUAUXTX_BIN=self.runtime)
        Path(self.env["HOME"]).mkdir()
        self.count = 0

    def check(self, condition, detail="assertion failed"):
        self.count += 1
        assert condition, detail

    def run(self, command, *, cwd=None, ok=True, env=None):
        result = subprocess.run(command if isinstance(command, str) else [str(a) for a in command], cwd=cwd or self.cwd,
                                env=env or self.env, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=180)
        output = result.stdout + result.stderr
        self.check((result.returncode == 0) == ok, f"{command}\n{output}")
        return output

    def cli(self, *args, **kwargs):
        return self.run([self.runtime, ROOT / "src/main.luau", *args], **kwargs)

    def package(self, name, bins=None, dependencies=None):
        directory = self.base / name
        directory.mkdir()
        lines = ["[package]", f'name = "{name}"', 'version = "1.0.0"', 'entry = "init.luau"', "[dependencies]"]
        for k, v in (dependencies or {}).items():
            lines.append(f'{json.dumps(k)} = {json.dumps(v)}')
        lines.append("[bin]")
        for command, entry in (bins or {}).items():
            lines.append(f'{json.dumps(command)} = {json.dumps(entry)}')
        (directory / "xtpkg.toml").write_text("\n".join(lines) + "\n", encoding="utf-8")
        (directory / "init.luau").write_text("return {}\n", encoding="utf-8")
        for entry in (bins or {}).values():
            target = directory / entry
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('local json = require("serde/json")\nlocal a = {}\nfor i=3,#process.argv do table.insert(a,process.argv[i]) end\nprint(json.encode(a))\n', encoding="utf-8")
        return directory

    def launch(self, executable, arguments):
        if os.name == "nt":
            # Quote even shell metacharacters that list2cmdline leaves bare.
            command = '"' + str(executable) + '" ' + " ".join('"' + a.replace('"', '\\"') + '"' for a in arguments)
            return self.run(subprocess.list2cmdline([os.environ["COMSPEC"]]) + ' /d /v:off /s /c "' + command + '"')
        return self.run([executable, *arguments])
