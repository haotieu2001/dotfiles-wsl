# 08 - AI tools, and what this repo leaves alone

One notes file, shared by every AI coding tool. This part of the setup works the
same everywhere, because it is only files in your home folder.

## `home/AGENTS.md`

One file, linked by `home.nix` to the place each tool looks for it:

```nix
home.file.".codex/AGENTS.md".source             = ... "${dotfiles}/home/AGENTS.md";
home.file.".config/opencode/AGENTS.md".source   = ... "${dotfiles}/home/AGENTS.md";
```

Each tool looks for your instructions in a different folder under a different
name. Pointing them all at one file means you write your preferences once, and
switching tools does not mean teaching them again.

It is a live link, so an edit applies to the next session with no rebuild.

### The rules, and why they are there

**Never use the em dash.** It is a common sign of text written by a model. This
matters most in commit messages and pull request text.

**Never add the AI tool as a commit co-author.** A person is responsible for the
change no matter who typed it, so that line adds noise and no information.

**Never edit `CHANGELOG.md` or other generated files by hand.** The generator
overwrites your edit, and until it does, the change confuses reviewers.

**Do not worry much about how long something takes to build. Prefer quality,
simplicity, reliability and long-term maintenance.** This is the most important
rule and the least obvious one.

The reason: models learn from text written by people, and people think in days
and weeks. So a model carries a sense of cost that matches human speed. When
choosing between two designs, it leans towards the quick one to save time that
an AI tool would not actually have spent. This rule corrects that.

**Start bug fixes by reproducing the problem the way a user would.** Without
this, a tool tends to guess a likely cause and fix something that was never
broken.

**Be fussy about how things look, and fix problems you notice along the way.**
This includes lint warnings, failing tests and flaky tests. AI tools read their
task narrowly by default. This tells them to look wider.

**For one-off jobs, take the simplest direct route.** This balances the rule
above. Do not build wrappers, extra layers or automation until something real
calls for them.

**Ask before starting a large group of sub-tasks at once.** They cost a lot and
are hard to follow. Get permission first.

### The WSL part

These are the mistakes a tool would otherwise make on this particular computer:

```markdown
- Keep repositories under the Linux filesystem (~/...), never under /mnt/c.
- Windows executables are callable from here (clip.exe, explorer.exe,
  powershell.exe). Use wslpath to convert between path styles.
- Do not install system packages with apt. This environment is managed by
  home-manager: add the package to home.packages in home.nix and run ./rebuild.sh.
```

The first one is about speed. `/mnt/c` is the Windows disk seen from Linux. It
is roughly ten times slower for the many-small-files work that builds and
searches do, and it does not keep Linux file permissions. A tool that clones a
project there gives you a setup that is slow for reasons nobody can see.

The third protects the whole idea of this repo. A tool that fixes a missing
program with `sudo apt install` has quietly created something no rebuild can
recreate. That is exactly the drift Nix is here to stop.

## Why `~/.claude/` is left alone

It would seem natural to link Claude Code's `settings.json` and `CLAUDE.md` like
everything else. This repo does not, and the reason applies beyond Claude Code.

`mkOutOfStoreSymlink` **replaces** a file, it does not merge into it. Point it at
a path that already holds a real file and home-manager moves the original out of
the way and puts a link there. For files this repo wrote itself, like Neovim and
herdr settings, that is exactly what you want. For `~/.claude/settings.json` it
is not:

- **The tool writes to it.** Change the theme or the model inside Claude Code and
  it rewrites `settings.json`. With a live link, those writes land in your repo
  and show up as changes you did not make.
- **You probably already had one.** A status line, a model choice, an API
  setting. Using this repo should not quietly replace those with someone else's.
- **Paths from one computer leak in.** A status line pointing at
  `/home/you/.claude/my-statusline.sh` does not work anywhere else, and this repo
  is meant to be shared.

So `~/.claude/` stays entirely local: logins, history, caches, *and* settings. If
you want your Claude setup saved in git, use a private repo rather than folding
it into this one.

The same test works for anything else you want to add: **does this repo own the
file completely, and does nothing else write to it?** If either answer is no,
leave it alone.

### Claude Code itself is not in `home.packages` either

Same idea, one level up. `claude-code` is in nixpkgs, but it updates itself into
`~/.local/bin/claude`. Installing it through Nix locks it to whatever
`flake.lock` says, puts it *ahead* of the self-updating copy, and leaves you
running an old version without noticing. Let it look after itself.

## Adding another tool

```nix
home.file.".config/<agent>/AGENTS.md".source =
  config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
```

Then run `./rebuild.sh`.
