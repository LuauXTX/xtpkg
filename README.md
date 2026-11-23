# XTPKG

XTPKG is a LuauXTX package manager with local path dependencies, an approval-based
Git registry, deterministic SemVer resolution, verified caching, and reproducible
installations. The implementation is Luau and uses LuauXTX's existing filesystem,
HTTP, crypto, and process APIs. It never runs package install hooks.

Requires a current native **LuauXTX** runtime and **Git** on PATH. Link checks
currently use Windows PowerShell on Windows, or `sh` and `find` on Unix. Python
3.10+ is needed only for the integration test runner.

Run the CLI from a project directory:

```powershell
luauxtx D:/GitHub/Repositories/xtpkg/src/main.luau init my-app
```

Or install the `xtpkg` command using the user-level installers below. Installed
launchers resolve the CLI independently of your current working directory.

## Install XTPKG

Install LuauXTX and Git first, then clone/download a trusted copy of this repository.
The scripts verify both tools; they do not download a runtime, use administrator
privileges, run package hooks, or install anything system-wide.

```sh
# Linux or macOS, from the XTPKG checkout
sh install.sh
```

```powershell
# Windows, from the XTPKG checkout
.\install.cmd
```

Restart your terminal application after installation. You can then run
`xtpkg --version` from any directory. Existing terminal processes keep their old
PATH; Unix users can instead reload their shell profile. On Windows the installer
updates only the current user's registry PATH, preserves its value type and
literal environment-variable references, and broadcasts an environment change.
It does not use `setx` or truncate/rewrite the system PATH. Unix setup maintains an
idempotent marked block in `.profile` and `.bashrc`, existing `.bash_profile`, and
zsh startup files when zsh is selected/present. Fish users receive a `conf.d`
entry. Other profile content and existing access permissions are preserved.

Default locations:

| Purpose | Windows | Linux/macOS |
| --- | --- | --- |
| XTPKG app | `%LOCALAPPDATA%/xtpkg/app` | `$XDG_DATA_HOME/xtpkg/app` |
| XTPKG command | `%LOCALAPPDATA%/xtpkg/bin/xtpkg.cmd` | `$XDG_DATA_HOME/xtpkg/bin/xtpkg` |
| Global project | `%LOCALAPPDATA%/xtpkg/global` | `$XDG_DATA_HOME/xtpkg/global` |
| Global commands | `<global-project>/bin` | `<global-project>/bin` |

On Unix, unset `XDG_DATA_HOME` defaults to `~/.local/share`. Both executable
directories are added to the user's PATH without adding duplicate entries. An
unrelated `xtpkg` already on PATH causes a conflict instead of silently selecting
the wrong installation; remove its obsolete PATH entry or use `--no-path` for a
side-by-side portable install.

```text
sh install.sh --prefix "/my/user/xtpkg" --no-path
install.cmd --prefix "D:\My Tools\xtpkg" --no-path
```

`--prefix` changes the app/bin installation root. It does not move configuration,
registry settings, caches, or global packages. `--no-path` leaves PATH/profiles
alone. `LUAUXTX_BIN` can select a native runtime explicitly; Windows setup can
also resolve a batch runtime shim to its actual `.exe`. Installed commands invoke
that native executable directly with correctly quoted arguments, including empty
arguments and shell metacharacters. Reinstall if the native executable moves.

To reinstall or upgrade, run the same installer from the newer checkout with the
same prefix. It stages the new app, validates startup, and swaps the app and its
managed launcher directory with rollback on failure. If XTPKG's own
`xtpkg.toml` declares dependencies, setup installs them into the staged app using
the normal resolver/installer; it never runs `[scripts]` or other install hooks.
The current manifest needs no third-party dependencies. Existing configuration,
registry choices, caches, and global packages are preserved.

An interrupted setup leaves `.xtpkg-setup-operation` containing a journal and
backups. After confirming no installer is running, repeat the same command with
`--recover` (and the same prefix). Recovery restores the previous app/bin before
reinstalling, or finishes cleanup if the prior operation already committed. Do
not delete its backups before recovery. PATH file replacements are atomic; a
process killed while updating several profiles may leave some new PATH entries,
which recovery/reinstallation completes safely. Managed directories containing
unrelated or modified launchers are refused rather than overwritten.

These are local source installers, not scripts intended for `curl | sh`.

## Project manifest

```toml
[package]
name = "my-app"
version = "0.1.0"
entry = "src/main.luau"
description = "My application"
license = "MIT"
repository = "https://github.com/YOUR_ACCOUNT/YOUR_REPOSITORY"

[dependencies]
"example/json" = "^1.2.0"
localutil = "path:../localutil"

[scripts]
start = "luauxtx src/main.luau"

# Optional executable entrypoints, exposed when installed globally.
[bin]
my-tool = "src/main.luau"
```

Description, license, and repository are optional for private projects and
required for publishing. Names may be `name` or `scope/name`, with lowercase
ASCII letters, digits, hyphens, and underscores. Unsafe Windows device names
are rejected on every platform. Entries must be relative `.lua`/`.luau` paths.

The supported manifest sections contain scalar TOML values; dependency and
script values must be quoted strings. `[bin]` maps command names to safe relative
`.lua`/`.luau` files; each declared file must exist in the verified package.
Omit `[bin]` entirely for a library. Command names are portable, unscoped lowercase
names; Windows device names and unsafe paths are rejected. Basic/literal strings,
comments, and quoted keys are supported. Multiline strings, inline dependency
tables, and arrays in these supported sections are rejected.
Other tables and their values are retained when editing dependencies. Existing
package metadata, scripts, and unrelated text are preserved; dependency keys
are sorted when their section is edited. `local/testproj` remains an ignored
local project and is never a registry.

## Commands

| Command | Behavior |
| --- | --- |
| `init [name] [--force] [--no-git] [--no-gitignore]` | Create project files, initialize Git when needed, and append missing ignore rules |
| `add name[@range]` | Resolve, install, and save a registry dependency |
| `add path:../package` | Install a local package, inferring its declared name |
| `add name@path:../package` | Install a local package with an identity check |
| `add name@git+https://host/repo#COMMIT --allow-git` | Explicit external Git dependency; COMMIT must be 40 lowercase hex characters |
| `remove name` | Remove a direct dependency and prune unused packages |
| `install` | Reproduce the current lock; resolve if roots changed or a lock is absent/legacy |
| `install --locked` | Require a valid matching v2 lock; allow downloads, forbid lock changes |
| `install --frozen` | Require a valid matching v2 lock; no registry/resolution/network; use verified cached artifacts only |
| `install --offline` | No network or source downloads; may resolve using cached registry metadata |
| `update [name]` | Update within declared ranges; preserve other compatible locked versions for a targeted update |
| `list [--tree]` | Show direct dependencies or resolved dependency relationships |
| `search [term]` | Search registry names and descriptions using its index |
| `info name` | Show metadata, versions, and immutable revisions |
| `outdated` | Show current, highest range-compatible, and latest stable versions |
| `publish [--dry-run] [--output file]` | Validate a clean committed package and prepare a registry PR submission |
| `cache path/list/verify/clean` | Inspect, verify, or remove managed cache entries |
| `config get registry` | Show the effective registry |
| `config set registry URL` | Persist an HTTPS registry base or absolute local directory |
| `run script` | Execute an explicitly selected script from the project manifest |
| `help [command]`, `version`, `--version` | Usage and version information |

Global options: `--help`/`-h`, `--verbose`/`-v`, `--quiet`/`-q`, `--offline`.
`add`, `remove`, `update`, `list`, and `install` also accept `--global`/`-g`.
`--quiet` suppresses progress; requested data and errors still print. Verbose
mode includes diagnostic tracebacks. Ordinary command errors return status 1
without a traceback. Argument-count and unsupported-option errors are checked.
`run` intentionally executes a user-selected project shell command, never
dependency scripts. The manifest schema does not accept install hooks.

Use shell quoting for version ranges, especially `<`, `>`, and `^` in shells
where they have special meanings. Examples: `xtpkg add 'example/json@^1.2.0'`.
Some third-party `.cmd` launchers strip carets while forwarding arguments. Use
the native LuauXTX executable directly if a saved range loses its `^`; the test
runner resolves such launchers to their native executable before argument tests.

## Initialize a project

`xtpkg init [name]` creates `xtpkg.toml` and `src/main.luau`, initializes a Git
repository only when no repository exists here or in an ancestor, and creates
or updates `.gitignore`. Parent repositories, worktrees/submodules (`.git`
files), bare repositories, and existing Git metadata are preserved; no nested
repository is initialized. User Git preferences such as the default branch are
respected. Init does not stage files, create commits, or install Git hooks.

Ignore updates append only missing entries. Existing bytes, comments, rules,
line endings, and permissions remain intact; a missing final newline is added
before appending new rules. Repeating `init --force` does not add duplicates or
rewrite an already complete `.gitignore`. Existing `packages/` or `packages`
rules also satisfy the root `/packages/` entry.

The defaults are `/packages/`, `.xtpkg-*`, `*-submission.json`, `.env`, `.env.*`,
`.DS_Store`, `Thumbs.db`, `Desktop.ini`, `.idea/`, `.vscode/`, `*.swp`, `*.swo`, and
`*~`. They do not ignore `xtpkg.lock`; the `!/xtpkg.lock` exception keeps it
trackable even when an existing broad rule such as `*.lock` is present. Existing
user rules and their order are never removed or rewritten.

```text
xtpkg init my-app
xtpkg init my-app --no-git            # still writes .gitignore
xtpkg init my-app --no-gitignore      # still initializes Git when appropriate
xtpkg init my-app --no-git --no-gitignore
```

The two options are independent. `--no-git` performs no Git initialization or
discovery commands, and `--no-gitignore` leaves an existing file untouched (or
does not create one). `--force` permits replacing an existing manifest; it does
not overwrite source files or existing ignore content. Missing Git, failed Git
discovery/initialization, or repository environment overrides produce a warning
while leaving the created project files usable. You can run `git init` manually
after correcting the Git installation/configuration. If ancestor metadata cannot
be checked safely, automatic Git initialization is skipped.

## Global packages

```text
xtpkg add --global example/tool
xtpkg add -g example/library
xtpkg add -g path:../my-tool
xtpkg list -g --tree
xtpkg update -g example/tool
xtpkg install -g --frozen
xtpkg remove -g example/tool
```

The global directory is a standalone project with its own `xtpkg.toml`,
`xtpkg.lock`, `packages/`, and managed `bin/`. The existing resolver, verified
cache, lockfile semantics, and package installer are reused. Your current local
project is not read or changed. Relative path additions resolve from the calling
directory and are saved as absolute paths in the global manifest. Override the
global root with `XTPKG_GLOBAL_DIR` for a portable installation or isolated tests.

Only explicitly added global roots expose their `[bin]` commands. Transitive
dependencies do not add executables to PATH. Libraries without `[bin]` are fully
supported and remain available under the global project's normal package/import
layout. They are not silently injected into local projects' import resolution.

Global installs validate and stage launchers before changing any packages,
manifest, or lockfile. The bin directory participates in the same rollback.
Updates regenerate commands, and removal prunes obsolete commands and unused
dependencies. No package code is executed during these operations.

Conflicting command declarations, an unrelated executable already on PATH, a
modified/missing managed launcher, or foreign files in a managed bin directory
cause an error before replacement. `xtpkg` and required host-tool names such as
`git`, `sh`, and `luauxtx` are reserved. At most 256 commands may be exposed.
Move/restore customized launchers before retrying; no force-overwrite is implicit.
The XTPKG installer sets up the global bin PATH entry. When invoking the source
CLI without installing XTPKG first, global operations print the bin location and
PATH setup guidance instead of editing shell profiles themselves.

## Registry setup

There is **no default production registry**. Start with the empty template in
[`registry/`](registry/README.md), or create a GitHub repository with this layout:

```text
index.json
packages/example/json.json
```

Configure its raw content base URL, replacing the account, repository, and branch:

```text
xtpkg config set registry https://raw.githubusercontent.com/YOUR_ACCOUNT/YOUR_REGISTRY/YOUR_BRANCH
xtpkg search json
xtpkg add example/json
```

`XTPKG_REGISTRY` overrides saved configuration. A local registry directory works
without a web server. HTTPS Git sources work from either registry type. For
fully local fixtures, metadata may use an **absolute local Git repository path**
as its source URL only when the registry itself is local and the command has
`--allow-local-sources`. This opt-in is also required to reinstall such locks,
including in offline/frozen mode. Remote registries cannot activate this feature.

Index schema:

```json
{
  "registry_version": 1,
  "packages": {
    "example/json": {
      "path": "packages/example/json.json",
      "description": "JSON utilities"
    }
  }
}
```

Each metadata record has `name`, `description`, `repository`, and a `versions`
object. Each version has `source = { type: "git", url, revision }`, dependencies
as version-range strings, and optional `entry` and `integrity`. Revisions must
be full immutable Git commits; a tag/ref without a commit is rejected. Publishing
generates the exact record, including a checksum, so no illustrative fake
revision needs to be copied. Registry and external Git packages can depend only
on registry version ranges. Local private packages may use paths too.

Configuration defaults to `%APPDATA%/xtpkg/config.json` on Windows and
`$XDG_CONFIG_HOME/xtpkg/config.json` or `~/.config/xtpkg/config.json` on Unix.
`XTPKG_CONFIG_HOME` overrides the parent config directory.

## Publishing and manual approval

1. Put `xtpkg.toml`, the entrypoint, a `LICENSE`, `LICENSE.md`, or `LICENSE.txt`,
   and every package file under Git version control. Set package description,
   license, and a credential-free HTTPS repository URL.
2. Commit the version being submitted. Use `.gitignore` for generated/private
   files, and keep the repository working tree clean, including untracked files.
3. Run `xtpkg publish --dry-run`. This validates the committed Git tree, metadata,
   identity, dependency ranges, safe paths, entrypoint, and supported text files.
   It writes no project/cache files and creates no submission. Temporary bare
   Git storage outside the project is removed after validation.
4. Run `xtpkg publish --output submission.json`. The output must be a new, safe
   relative filename whose parent already exists. Existing files are never
   overwritten. The output is a package metadata record containing one version.
5. Push the referenced commit to the declared repository yourself. Submit a PR
   to the registry that merges this new version into its package metadata file
   and adds/updates the discovery index. **Preserve every existing version.**
6. Registry maintainers review the code and metadata, validate the registry,
   and approve the submission by merging the PR. Installation needs no GitHub
   authentication for public repositories. There is no public write API.

Ignore or move generated submissions before a subsequent clean-tree publish
check. Publishing checks local committed contents; it does not verify that a
commit has already been pushed or that the declared remote serves that commit.

## Resolution, lockfiles, and migration

Version precedence follows [SemVer 2.0](https://semver.org/spec/v2.0.0.html),
including numeric prerelease identifiers and ignored build metadata. Supported
ranges: exact, `^`, `~`, `>=`, `<=`, `>`, `<`, whitespace intersections such as
`>=1.0.0 <2.0.0`, `1.2.x`/`1.2.*`, and `*`. Prereleases are excluded unless a
range explicitly includes a prerelease with the same major/minor/patch tuple.
OR ranges, hyphen ranges, and abbreviated versions are currently unsupported.

The resolver deterministically tries highest compatible versions, with bounded
backtracking and preference for compatible existing locks. One version per name
is installed; incompatible graphs fail with requirement chains. Cycles fail.
Limits: 256 packages, 256 declarations per manifest, 128 graph depth, and 10,000
resolution attempts. An unscoped package cannot also be another package's scope.

`xtpkg.lock` remains TOML. Format 2 extends the previous package map with roots,
name, version, source, exact revision, SHA-256 integrity, entrypoint, requirements,
and resolved dependency versions. Dependency maps are canonical JSON strings
inside TOML scalars, avoiding unsupported runtime TOML nesting behavior.
Unchanged roots reuse the exact graph, even if registry metadata changes.

Legacy format 1 locks are read and migrated by a normal `install`; they cannot
meet `--locked`/`--frozen` because they lack immutable artifact identities.
An old `packages/` tree is adopted only when all top-level directories match
the legacy lock. An unmarked unrelated tree is refused.

Local paths are immutable snapshots in a lock: normal installs reproduce the
snapshot, and `update` refreshes it. Moving a project invalidates locked relative
path roots if their absolute source location changes. `--offline` cannot create
a fresh local snapshot; it needs an existing lock/cache. Frozen mode does not
need a registry configuration at all.

## Runtime imports

LuauXTX currently supports relative/absolute file imports and built-in modules;
it does not resolve bare registry names. XTPKG implements its side without
changing runtime code in another repository:

```luau
-- src/main.luau in the application
local packages = require("../packages/.xtpkg-imports")
local json = packages.require("example/json")

-- Or use the generated relative wrapper directly:
local sameJson = require("../packages/example/json")
```

Every package has a sibling `.luau` wrapper that imports its declared entrypoint.
Its original files live under `packages/<name>/`. Packages can use ordinary
relative imports to sibling dependency wrappers: an `example/json` package with
an entry at `init.luau` imports `example/core` via `require("../core")`.
Adjust relative paths for deeper entrypoints. Existing internal relative imports
are preserved. No bare `require("example/json")` support is claimed.

`packages/.xtpkg-imports.json` is the runtime integration contract: each name
maps to a relative wrapper path, original entry, resolved version, and revision.
The generated `.xtpkg-imports.luau` adapter captures LuauXTX's directory-bound
`require` before exposing its named lookup function. Package code should likewise
capture `local moduleRequire = require` at module scope when requiring modules
inside functions, matching this runtime's current loader behavior.

## Integrity, safety, cache, and transactions

Artifacts are UTF-8 text Git trees or local snapshots, up to 2,048 files, 1 MiB
per file, and 16 MiB of contents. Portable paths use ASCII letters, digits,
spaces, `.`, `_`, `-`, `+`, `@`, parentheses, and `/` separators. Unicode filename
collisions and Windows short-name aliases are avoided by rejecting other
characters; file contents may contain Unicode. Case collisions and
file/directory collisions are rejected, and Git symlinks/submodules are refused.
No archive extraction or checkout occurs. Git blobs are checked against their
original Git object IDs after transport through the runtime's text process API.
Native libraries, executables, archives, credential files, `.env` files, and
tracked build/dependency output directories are rejected. Pure Luau is the
supported package type; native capabilities are reserved and rejected.

Integrity is SHA-256 of the canonical JSON object mapping every package-relative
filename to its complete UTF-8 text, with keys sorted, standard short JSON
escapes, and unescaped UTF-8 characters. This excludes generated wrappers and
includes the original manifest. Publish emits this checksum; installation
compares it when provided and always records a verified snapshot checksum.
An immutable Git object identity plus checksums detects changed bytes, but does
not establish author identity or code trust. This registry has no signatures.

Cache defaults: `%LOCALAPPDATA%/xtpkg/cache`, `$XDG_CACHE_HOME/xtpkg`, or
`~/.cache/xtpkg`. Override the exact root with `XTPKG_CACHE_DIR`. Metadata keys
include registry location; artifact keys include source, name, version, and
revision. Every cache read verifies its envelope checksum, and package reads
also check contents and manifest identity. Corruption fails; run `cache clean`
and reinstall online to repair it. Cleanup checks ownership and deletes only
known managed files. It never recursively deletes a configured cache root.

Install/add/remove/update acquire a project operation guard, build a complete
staging tree, and rename backups and replacements with rollback on ordinary
failures. Project manifests and locks are replaced only after downloads and
validation succeed. `packages/` is a managed directory: do not store unrelated
files inside it. Unrelated project files outside it are never replaced.

## Validation and current limits

```text
python -u tests/run.py
python -u tests/run.py --runtime /absolute/path/to/luauxtx
python -u tests/global.py
python -u tests/init.py
python -u tests/installers.py
python -u tests/posix.py
```

The runner creates temporary Git packages and a registry, exercises the real
LuauXTX CLI and imports, and uses no public services. Unit suites cover parsing,
SemVer, names, paths, metadata, resolver backtracking/conflicts/cycles, and cache
snapshot validation. The HTTPS client is tested with mocked responses, including
oversized and malformed bodies and a failing transport. Integration coverage includes exact commits, lock reuse,
targeted/all updates, offline resolution, frozen reproduction, corrupted/missing
artifacts, failed fetches, injected transaction rollback, removal, path imports,
publishing, registry immutability validation, Git symlinks, filesystem junctions,
legacy migration, unmanaged directory preservation, configuration, and cache cleanup.
Global tests cover library-only packages, direct/transitive executable exposure,
local isolation, PATH/name conflicts, updates, cleanup, frozen installation, and
rollback. Installer tests cover dependency bootstrap, hook avoidance, reinstall,
configuration/cache preservation, Unicode paths, argument boundaries, PATH
idempotence, modified launchers, injected failures, and abrupt-interruption
recovery. Windows PATH tests use a disposable registry key and temporary profiles,
never the real user PATH. `XTPKG_PATH_PROFILE` selects a custom profile file for
isolated/portable testing instead of the default profile/registry backend.
Project initialization tests cover new/existing/parent/bare repositories,
worktree Git files, append-only CRLF files, duplicate prevention, lockfile
visibility, both opt-outs, missing/failed Git, and redirected Git environments.

`.github/workflows/test.yml` builds a pinned LuauXTX revision and runs the suites
on Windows, Ubuntu, and macOS. On this development host the native Windows tests
and POSIX shell tests under Git Bash can run; native Linux/macOS execution needs
that CI matrix (the local WSL VM cannot start).

Known limits and follow-up work:

- No native dependencies, install hooks, arbitrary archive sources, signatures,
  credential manager, private registry auth, or automatic GitHub PR creation.
- The runtime HTTP client buffers responses before XTPKG can enforce its 2 MiB
  parsing limit; it exposes no streaming body limit or request timeout. Git fetch
  size and execution time are also not bounded by the current process API.
- The runtime lacks `lstat`, safe directory handles, binary process output, and
  a filesystem transaction primitive. OS link checks reject existing escapes,
  but cannot eliminate malicious concurrent filesystem changes (TOCTOU).
- Rollback handles reported errors, not power loss or a process killed during
  rename. Interrupted `.xtpkg-stage-*` backups and `.xtpkg-operation` guards need
  manual inspection/recovery before reuse. Cache clean refuses unknown temporary
  directories left by interrupted fetches.
- The user-level XTPKG installer adds an explicit journal/recovery path for app
  upgrades. Global package operations retain the package installer's existing
  interruption-recovery limits described above.
- The automated suite runs on the current Windows environment; Unix branches
  need platform CI. Public HTTPS retrieval and GitHub hosting need an integration
  smoke test once a real registry is configured.
- LuauXTX's current loader caches paths without canonicalizing `..`/`.` segments.
  Different import spellings may instantiate a module more than once. Use a
  consistent import adapter/path convention until the runtime canonicalizes keys.
- Next runtime improvements: bounded HTTP/process APIs, non-following filesystem
  metadata/handles, and a native consumer for `.xtpkg-imports.json`. Next registry
  improvements: CI immutability checks, code review policy, and signed provenance.
