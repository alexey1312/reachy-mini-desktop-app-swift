# One-command device runs, and a sim venv that costs seconds

Two local-workflow problems, solved separately but shipped together because both are about what a fresh
Conductor worktree costs before it is useful.

## Problem

**Device builds are a recipe, not a command.** Building onto the iPhone means copying four commands out of
`CLAUDE.local.md`, which is gitignored and therefore exists **only** in the main checkout — no Conductor
workspace has it. Every device build starts by reading a file from another directory by absolute path.

**`.venv-sim` costs 10–15 minutes and 1.3 GB per worktree.** `mise run sim-daemon` builds it with
`python -m venv` + `pip install`, and pip copies every file out of its cache. Moving the venv outside the
worktree to share it is a known dead end: both a relocated copy and a clean install under `~/.cache` leave the
daemon stuck before it binds `:8000`, logging `External plugin loader failed`, while the same venv inside the
worktree serves in four seconds. The cause was never identified.

## Design

### 1. `mise run device`

One task: build for the phone, install, launch. It replaces the `CLAUDE.local.md` recipe.

**Device identity is discovered, not configured.** `xcrun devicectl list devices --json-output` returns both
identifiers in one record — `identifier` (the CoreDevice UUID `devicectl` wants) and
`hardwareProperties.udid` (what `xcodebuild -destination 'id=…'` wants). The task selects iOS devices with
`pairingState == "paired"` and `tunnelState != "unavailable"`, and takes the single match. Two matches is an
error that lists the candidates and tells the user to set `REACHY_DEVICE_UDID`.

That leaves exactly one value that cannot be discovered: the signing team. Five teams exist on this machine and
only `J52C3SB8K5` owns `com.alexey1312.*`, so guessing is not an option.

**The one secret lives in one file, outside every worktree:** `~/.config/reachy-mini/device.env`, holding

```sh
REACHY_DEVELOPMENT_TEAM=XXXXXXXXXX
```

Nothing has to be copied between worktrees because the file is not in any of them. An already-set environment
variable wins over the file, so CI or a second machine can override without editing anything. If neither is
present the task exits non-zero and prints how to create the file — it never guesses a team and never falls
back to unsigned.

Logic goes in `Scripts/device-run.sh` rather than inline in `mise.toml`: it parses JSON, branches on error
cases, and is called from two places (the mise task and the Conductor run button).

**The one click.** `.conductor/settings.toml` gains a run script, so the workspace has a button:

```toml
[scripts.run.device]
available_in = [ "local" ]
command = "./bin/mise run device"
icon = "smartphone"
```

Repository settings are read from the default branch on the remote, so the button appears only after this
merges to `main`. The file carries no secrets — the team id stays in `~/.config`.

**Flags:** `--no-launch` (install only), `--build-only`, `--device <udid>`. Nothing else; the recipe being
replaced has no other modes.

### 2. `uv` as the installer for `.venv-sim`

The venv stays exactly where it is — `.venv-sim` inside the worktree, created by `python -m venv` from mise's
pinned 3.12. The relocation dead end is not revisited. Only the installer changes:

```sh
uv pip install --python "$VENV/bin/python" --requirement "$REQUIREMENTS"
```

uv writes packages as APFS clones (copy-on-write) instead of copying them, so a second worktree pays for
metadata and nothing else. `uv` is pinned in `mise.toml` `[tools]` like every other tool; it is currently only
present via Homebrew, which the project rules forbid relying on.

Measured on this machine, warm cache:

|                                | `pip` (today)                              | `uv`       |
| ------------------------------ | ------------------------------------------ | ---------- |
| Install time                   | 10–15 min cold, "a couple of minutes" warm | **0.45 s** |
| Disk consumed by a second venv | ~1.3 GB                                    | **6 MiB**  |

The `mise.toml:271` comment "uv has known MuJoCo issues" is stale for this usage and is replaced by what was
measured: with the venv created by `python -m venv` and uv used only as the installer, `mjpython` is present,
`reachy-mini` reports `1.9.0`, and the daemon answers `/api/daemon/status` with
`"state":"running","simulation_enabled":true`. Verified before writing this document.

The existing `.requirements.sha256` stamp, the `libgstpython.dylib` disabling and the `GST_PLUGIN_SCANNER`
export are untouched — they are about running the daemon, not about installing it.

**Fallback, if uv ever breaks a mujoco upgrade:** clone a sibling worktree's venv with `cp -c -R` and rewrite
the absolute paths in `bin/*` shebangs and `pyvenv.cfg`. Not implemented — it is fragile and, at 0.45 s, buys
nothing.

## Error handling

| Situation                      | Behaviour                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------ |
| No team configured             | Exit 1, print the `~/.config/reachy-mini/device.env` snippet to create               |
| No paired iOS device           | Exit 1, name the check (cable/Wi-Fi, trust prompt)                                   |
| Two or more candidates         | Exit 1, list name + udid of each, suggest `REACHY_DEVICE_UDID`                       |
| Build fails                    | Propagate `xcodebuild`'s exit code; output already goes through xcsift               |
| `devicectl` provisioning noise | Ignored — it prints `No provider was found.` on every invocation and succeeds anyway |

## Verification

- Run `mise run device` from this worktree with the phone connected: app installs and launches.
- Unset the team, run again: exits 1 with the config snippet, builds nothing.
- Delete `.venv-sim`, run `mise run sim-daemon`, time it and poll `/api/daemon/status`.
- `mise run lint` + `format-check` stay green (`actionlint` covers the workflow, `shellcheck` is not wired in).

## Out of scope

- Sharing one venv between worktrees — the documented dead end.
- Auto-detecting the signing team from the keychain: five teams, no reliable signal for which owns the bundle id.
- A `mise.local.toml` per worktree: that is the `CLAUDE.local.md` problem again, one file per worktree with no
  propagation.
- Migrating `CLAUDE.local.md` away is a follow-up: once `mise run device` works, what remains in it is the team
  id (now in `~/.config`) and prose that belongs in `AGENTS.md` without the id.
