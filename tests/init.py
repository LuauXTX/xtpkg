"""Real Git and filesystem tests for append-only project initialization."""
import os
from pathlib import Path
import tempfile
from support import Harness, ROOT, luau_string

with tempfile.TemporaryDirectory(prefix="xtpkg-init-tests-") as temporary:
    h = Harness(temporary)
    for variable in ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"):
        h.env.pop(variable, None)
    git_config = h.base / "gitconfig"
    git_config.write_text("[init]\n defaultBranch = test-main\n", encoding="utf-8")
    h.env.update(GIT_CONFIG_GLOBAL=str(git_config), GIT_CONFIG_NOSYSTEM="1")

    def project(name):
        directory = h.base / name
        directory.mkdir()
        return directory

    def git(cwd, *args):
        return h.run(["git", "-c", "core.hooksPath=", *args], cwd=cwd).strip()

    fresh = project("fresh")
    h.check("Initialized Git repository" in h.cli("init", cwd=fresh))
    h.check((fresh / ".git").is_dir())
    h.check(git(fresh, "symbolic-ref", "--short", "HEAD") == "test-main")
    ignored = (fresh / ".gitignore").read_bytes()
    for rule in (b"/packages/", b".xtpkg-*", b"*-submission.json", b".env", b".env.*", b".DS_Store", b"Thumbs.db", b"Desktop.ini", b".vscode/", b".idea/", b"!/xtpkg.lock"):
        h.check(ignored.splitlines().count(rule) == 1)
    (fresh / "xtpkg.lock").write_text("lockfile placeholder")
    h.run(["git", "check-ignore", "--no-index", "--quiet", "--", "xtpkg.lock"], cwd=fresh, ok=False)
    metadata = (fresh / ".git/config").read_bytes()
    modified = (fresh / ".gitignore").stat().st_mtime_ns
    h.cli("init", "--force", cwd=fresh)
    h.check((fresh / ".gitignore").read_bytes() == ignored)
    h.check((fresh / ".gitignore").stat().st_mtime_ns == modified)
    h.check((fresh / ".git/config").read_bytes() == metadata)

    existing = project("existing")
    prefix = b"# custom content kept byte-for-byte\r\n.env\r\npackages/\r\n*.lock\r\ncustom-entry"
    (existing / ".gitignore").write_bytes(prefix)
    if os.name != "nt": (existing / ".gitignore").chmod(0o600)
    h.cli("init", cwd=existing)
    updated = (existing / ".gitignore").read_bytes()
    h.check(updated.startswith(prefix + b"\r\n"))
    h.check(updated.splitlines().count(b".env") == 1)
    h.check(updated.splitlines().count(b"packages/") == 1 and b"/packages/" not in updated.splitlines())
    h.check(b"\n" not in updated[len(prefix):].replace(b"\r\n", b""))
    h.run(["git", "check-ignore", "--no-index", "--quiet", "--", "xtpkg.lock"], cwd=existing, ok=False)
    if os.name != "nt": h.check((existing / ".gitignore").stat().st_mode & 0o777 == 0o600)

    parent = project("parent")
    git(parent, "init", "--quiet", "--template=", ".")
    nested = parent / "child"
    nested.mkdir()
    env = dict(h.env, GIT_CEILING_DIRECTORIES=str(parent))
    h.cli("init", cwd=nested, env=env)
    h.check(not (nested / ".git").exists())
    h.check((nested / ".gitignore").exists())
    # Worktrees and submodules represent Git metadata with a .git file.
    (parent / "seed").write_text("fixture")
    git(parent, "add", "seed")
    h.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "core.hooksPath=", "commit", "-qm", "fixture"], cwd=parent)
    worktree = h.base / "worktree"
    git(parent, "worktree", "add", "--detach", str(worktree))
    pointer = (worktree / ".git").read_bytes()
    h.cli("init", "worktree", cwd=worktree)
    h.check((worktree / ".git").read_bytes() == pointer)
    workchild = worktree / "child"
    workchild.mkdir()
    h.cli("init", "workchild", cwd=workchild)
    h.check(not (workchild / ".git").exists())
    bare = project("bare")
    git(bare, "init", "--bare", "--quiet", "--template=", ".")
    barechild = bare / "child"
    barechild.mkdir()
    h.cli("init", "barechild", cwd=barechild)
    h.check(not (barechild / ".git").exists())

    no_git = project("no-git")
    h.cli("init", "--no-git", cwd=no_git)
    h.check(not (no_git / ".git").exists() and (no_git / ".gitignore").exists())
    no_ignore = project("no-ignore")
    h.cli("init", "--no-gitignore", cwd=no_ignore)
    h.check((no_ignore / ".git").is_dir() and not (no_ignore / ".gitignore").exists())
    untouched = b"# custom\r\nxtpkg.lock"
    (no_ignore / ".gitignore").write_bytes(untouched)
    h.cli("init", "--force", "--no-gitignore", cwd=no_ignore)
    h.check((no_ignore / ".gitignore").read_bytes() == untouched)
    neither = project("neither")
    h.cli("init", "--no-git", "--no-gitignore", cwd=neither)
    h.check(not (neither / ".git").exists() and not (neither / ".gitignore").exists())
    h.check("not supported" in h.cli("list", "--no-git", cwd=fresh, ok=False))

    # Missing/failed Git is nonfatal, and --no-git does not even invoke Git.
    for case in ("missing-git", "failed-git", "git-probe-failed", "git-disabled"):
        directory = project(case)
        script = h.base / (case + ".luau")
        script.write_text('''local command=require(%s)
local original=process.exec
local calls,initializations=0,0
process.exec=function(program,args,options)
 if program=="git" then
  calls+=1
  if %s then error("Git executable missing",0) end
  if table.find(args,"init") then initializations+=1; return {code=1,stdout="",stderr="fixture failure"} end
  return {code=%s,stdout="",stderr="fixture failure"}
 end
 return original(program,args,options)
end
command.run({_={"init",%s},["no-git"]=%s,log=print})
%s
''' % (luau_string((ROOT / "src/commands/init").as_posix()), "true" if case == "missing-git" else "false", "1" if case == "git-probe-failed" else "128", luau_string(case), "true" if case == "git-disabled" else "false", "assert(calls==0)" if case == "git-disabled" else ("assert(initializations==1)" if case == "failed-git" else "assert(initializations==0)")), encoding="utf-8")
        output = h.run([h.runtime, script], cwd=directory)
        h.check((directory / "xtpkg.toml").exists() and (directory / ".gitignore").exists())
        h.check("stack traceback:" not in output)
        if case != "git-disabled": h.check("warning:" in output)
    # An inherited GIT_DIR cannot cause init to create metadata outside the project.
    redirected = project("redirected")
    outside = h.base / "do-not-create"
    h.check("overrides" in h.cli("init", cwd=redirected, env=dict(h.env, GIT_DIR=str(outside))))
    h.check(not outside.exists() and not (redirected / ".git").exists())
    print(f"PASS: {h.count} Git/init integration assertions")
