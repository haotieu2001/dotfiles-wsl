# 08 - `AGENTS.md`, and what this repo deliberately does not manage

One memory file, fanned out to every coding agent. This is the part of the
setup that is entirely platform-independent, because agent config is just files
in `$HOME`.

## `home/AGENTS.md`

One file, symlinked to each agent's expected location by `home.nix`:

```nix
home.file.".codex/AGENTS.md".source             = ... "${dotfiles}/home/AGENTS.md";
home.file.".config/opencode/AGENTS.md".source   = ... "${dotfiles}/home/AGENTS.md";
```

Each agent looks for global instructions in a different place under a different
name. Fanning one file out to all of them means switching agents does not mean
re-teaching your preferences, and there is one place to edit.

It is a live symlink, so edits apply to the next agent session with no rebuild.

### The rules, and the reasoning behind them

**Never use the em dash.** A stylistic tell of model-generated text. Matters
most for commit messages and PR descriptions.

**Never auto-add the agent as commit co-author.** A human is accountable for the
change regardless of who typed it, so the trailer adds noise rather than
information.

**Never manually modify CHANGELOG.md or auto-generated files.** Edits there are
overwritten by the generator, and the diff misleads reviewers in the meantime.

**Do not give much weight to development cost; prefer quality, simplicity,
robustness, scalability, and long-term maintainability.** The most important
rule in the file, and the least obvious. The argument from 41:19: models are
trained on human-written material, and humans estimate in days and weeks. So a
model inherits a cost model calibrated to human speed and, when choosing between
designs, over-weights implementation effort - picking the cheap, unscalable
option to save time that an agent would not actually have spent. This rule
corrects that bias.

**Start bug fixes by reproducing end-to-end, as a user would.** Without this an
agent tends to jump to a plausible cause and fix a problem that does not exist.

**Be picky about UI, obsessed with pixel perfection, and fix what you notice
along the way.** Extends to lint, test failures, and flakiness. Agents default
to a narrow reading of scope; this widens it deliberately.

**Prefer the simplest direct path for one-off operational work.** The
counterweight to the rule above: do not build wrappers, control planes, or
policy layers until something concrete demands them.

**Ask before spawning large subagent swarms.** They are expensive and hard to
follow. Explicit approval first.

### The WSL section

These are the mistakes an agent will otherwise make on this specific machine:

```markdown
- Keep repositories under the Linux filesystem (~/...), never under /mnt/c.
- Windows executables are callable from here (clip.exe, explorer.exe,
  powershell.exe). Use wslpath to convert between path styles.
- Do not install system packages with apt. This environment is managed by
  home-manager: add the package to home.packages in home.nix and run ./rebuild.sh.
```

The first is a performance trap: `/mnt/c` is a 9p mount, roughly an order of
magnitude slower for the many-small-files access patterns that builds and greps
produce, and it does not preserve Unix permissions. An agent that clones a repo
there will produce a setup that is slow for reasons nobody can see.

The third protects the whole premise of this repo. An agent that "fixes" a
missing tool with `sudo apt install` has quietly created state that no rebuild
reproduces, which is precisely the drift Nix is here to prevent.

## Why `~/.claude/` is not managed

It would be natural to symlink Claude Code's `settings.json` and `CLAUDE.md`
alongside everything else. This repo deliberately does not, and the reason
generalises past Claude Code.

`mkOutOfStoreSymlink` is a *replacement*, not a merge. Point it at a path that
already has a real file and home-manager moves the original aside and puts a
symlink there. For config this repo authors from scratch - Neovim, herdr - that
is exactly right. For `~/.claude/settings.json` it is not, because:

- **The tool writes to it.** Change theme or model inside Claude Code and it
  rewrites `settings.json`. With a live symlink those writes land in your repo
  and show up as unexplained `git status` noise.
- **You probably already had one.** A status line, a model preference, an API
  setting. Adopting this repo should not silently swap that for someone else's.
- **Machine-specific paths leak.** A status line pointing at
  `/home/you/.claude/my-statusline.sh` is not portable, and this repo is meant
  to be publishable.

So `~/.claude/` stays entirely local: credentials, history, caches, *and*
settings. If you want your Claude config version-controlled, do it in a private
repo rather than folding it into this one.

The same test applies to anything else you are tempted to add: **does this repo
own the file outright, and does nothing else write to it?** If either answer is
no, leave it alone.

### Claude Code itself is not in `home.packages` either

Same principle, one level up. `claude-code` is in nixpkgs, but it self-updates
into `~/.local/bin/claude`. Installing it through Nix pins it to `flake.lock`,
puts it *ahead* of the self-updating copy on `PATH`, and leaves you running a
version that silently falls behind. Let it manage itself.

## Adding another agent

```nix
home.file.".config/<agent>/AGENTS.md".source =
  config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
```

Then `./rebuild.sh`.
