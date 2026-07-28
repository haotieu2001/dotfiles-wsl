# 08 - `AGENTS.md` and `.claude/settings.json`

The video's 39:36 chapter, and the part that carries over to WSL completely
unchanged, because agent config is just files in `$HOME`.

## `home/AGENTS.md`

One file, symlinked to three locations by `home.nix`:

```nix
home.file.".claude/CLAUDE.md".source            = ... "${dotfiles}/home/AGENTS.md";
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

Added here, not in the video, because these are the mistakes an agent will
otherwise make on this specific machine:

```markdown
- Keep repositories under the Linux filesystem (~/...), never under /mnt/c.
- Windows executables are callable from here (clip.exe, explorer.exe,
  powershell.exe). Use wslpath to convert between path styles.
- Do not install system packages with apt. Add the package to home.packages
  in home.nix and run ./rebuild.sh.
```

The first is a performance trap: `/mnt/c` is a 9p mount, roughly an order of
magnitude slower for the many-small-files access patterns that builds and greps
produce, and it does not preserve Unix permissions. An agent that clones a repo
there will produce a setup that is slow for reasons nobody can see.

The third protects the whole premise of this repo. An agent that "fixes" a
missing tool with `sudo apt install` has quietly created state that no rebuild
reproduces, which is precisely the drift Nix is here to prevent.

## `home/.claude/settings.json`

```json
{
  "theme": "dark-ansi",
  "statusLine": {
    "type": "command",
    "command": "input=$(cat); model=$(echo \"$input\" | jq -r '.model.display_name'); ..."
  }
}
```

`theme: dark-ansi` uses the terminal's own ANSI palette instead of Claude Code's
built-in colors, so the agent matches rose-pine rather than fighting it.

The status line is the 38:09 demo. Claude Code runs the command on each update
and pipes a JSON blob describing the session into it on **stdin**:

- `input=$(cat)` reads that blob.
- `jq -r '.model.display_name'` extracts the model name. This is why `jq` is in
  `home.packages`; without it the status line silently shows nothing.
- `.context_window.used_percentage // empty` extracts context usage, with `//`
  falling back to empty when the field is absent (it is missing early in a
  session).
- The `if` prints `model | ctx: N% used` when usage is known, otherwise just the
  model name.

Result: model and remaining context visible at all times, which is what makes it
obvious when a session is about to need compacting.

Only `settings.json` is symlinked, not all of `~/.claude/`. Credentials, project
history, and caches stay local and out of git - which matters, since this repo
is meant to be publishable.

## Adding another agent

```nix
home.file.".config/<agent>/AGENTS.md".source =
  config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
```

Then `./rebuild.sh`.
