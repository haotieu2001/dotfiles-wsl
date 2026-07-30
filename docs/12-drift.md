# 12 - Checking for drift

```bash
./scripts/check-drift.sh
```

Read-only. It changes nothing, it only tells you what it found.

## The problem it solves

This repo promises that a new laptop ends up the same as this one. That promise
only holds for software Nix installed. Anything that arrived another way -
`curl ... | sh`, `pip install --user`, `apt install`, a version manager like
nvm - is not in `flake.lock`, so it will not be on the new machine.

There are two ways that hurts, and the second is much worse than the first.

**Missing.** A tool exists here and not there. Annoying, but you find out fast:
the command is simply not found.

**Shadowed.** A tool exists in both places, and the wrong one runs. `home.nix`
says `nodejs_24`. The build really does contain `nodejs_24`. And when you type
`node`, you get nvm's copy, because `~/.nvm/.../bin` sits earlier on your
`PATH`. Nothing errors. The repo looks correct. It is describing a version of
Node you are not running.

That second case is invisible without a tool that goes looking, which is what
this script is.

## What it checks

**1. Declared tools vs what actually runs.** For every binary the built config
provides, it runs `command -v` and checks the answer resolves into
`/nix/store`. Two ways to fail:

- `x direnv is declared but not installed` - your profile is stale. `home.nix`
  gained a package and nobody ran `./rebuild.sh` since.
- `x node resolves to /home/you/.nvm/.../node` - shadowed, as above.

The list of tools comes from **building** the config, not from reading
`home.nix` as text. That is the only way to catch the stale case: a package can
be declared and absent at the same time, and text cannot tell you that.

**2. Non-Nix installers in `$HOME`.** Looks for `~/.nvm`, `~/.pyenv`,
`~/.cargo`, `~/.local/bin` and friends, with their sizes. These are marked `!`,
not `x`, because they are not breaking anything today. They are simply software
that will not exist on the next machine.

**3. PATH order.** Lists anything ahead of `~/.nix-profile/bin` that is not part
of the OS. This is the *cause* of every shadowed line in check 1. Fixing an
entry here usually fixes several lines up there.

**4. apt duplicates.** Packages apt installed that `home.nix` also declares.
`git` and `curl` are skipped on purpose: `bootstrap.sh` needs both before Nix
exists, so those apt copies are load-bearing.

## Reading the output

| Mark | Means |
| --- | --- |
| `ok` | nothing wrong |
| `!` | not managed by Nix, works here, will not be on a new machine |
| `x` | drift that changes which program you actually run |

Only `x` sets the exit status to 1. A run with nothing but `!` lines exits 0.

## Fixing what it finds

**Declared but not installed:** run `./rebuild.sh`.

**Shadowed:** decide which copy you want, then remove the other one. To drop
nvm, for example, delete the block it added to your shell startup file, then:

```bash
rm -rf ~/.nvm
```

Open a new shell and check:

```bash
command -v node      # want ~/.nix-profile/bin/node
```

**`~/.local/bin` ahead of the Nix profile:** this one needs a decision rather
than a delete, because useful things live there. `claude` is meant to be there
and is [documented in `home.nix`](02-home-nix.md) as a deliberate exception: it
updates itself, and the Nix store is read-only. `pip --user` scripts land there
too.

The narrow fix is to remove only the entries that shadow a declared tool. If
`uv` and `uvx` are the problem, and Nix already provides them:

```bash
rm ~/.local/bin/uv ~/.local/bin/uvx
```

The broader fix is to move `~/.local/bin` *after* `~/.nix-profile/bin` on your
`PATH`, so Nix wins by default and anything not in Nix still works.

**A language toolchain you actually need:** it probably belongs in that
project's own flake rather than in your home folder. That way the version
travels with the code. See [11-devshells.md](11-devshells.md).

## Why it is not part of rebuild.sh

`rebuild.sh` builds. This reports. Wiring a check into the build would mean
either failing a rebuild over something you deliberately installed, or printing
a warning often enough that you stop reading it.

It is also the wrong moment. Drift matters when you are about to trust this repo
to set up a new machine, not every time you add an alias. Run it then, and
whenever a tool behaves differently from what `home.nix` says it should.
