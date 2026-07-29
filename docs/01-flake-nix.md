# 01 - `flake.nix`

The starting file. A flake has two parts: `inputs`, which say where the code
comes from, and `outputs`, which say what to build from it.

Next to it sits `flake.lock`. That file writes down the exact version of every
input. It is the reason this setup gives the same result on every computer,
instead of just being a script that usually works.

## Line by line

```nix
{
  description = "dotfiles for WSL Ubuntu";
```

Just a label. You see it when you run `nix flake show`. It changes nothing.

```nix
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
```

Where packages come from. `nixos-26.05` is a stable branch. It gets security
fixes, but programs do not jump to new versions, so builds stay predictable.

Branches ending in `-darwin` are built for macOS only. On Linux you want
`nixos-<release>`, even though you are not running NixOS. Do not use
`nixpkgs-unstable` here. It changes all the time, which is the opposite of what
you want.

```nix
    home-manager.url = "github:nix-community/home-manager/release-26.05";
```

home-manager, on the branch that matches nixpkgs. **Keep these two numbers the
same.** Each home-manager release expects settings from the matching nixpkgs
release. Mixing `release-26.05` with `nixos-25.11` gives confusing errors.

```nix
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
```

Tells home-manager to use *our* nixpkgs instead of downloading its own. Without
this you would store two full copies of every package, and could end up with two
different builds of the same library at once.

```nix
    # No nix-darwin and no nix-homebrew here.
  };
```

A macOS setup would have these two. This one does not. nix-darwin only works on
macOS, and WSL Ubuntu has no system layer for Nix to plug into. See
[00-architecture.md](00-architecture.md).

```nix
  outputs = { self, nixpkgs, home-manager, ... }:
```

The function that builds the results. The `...` at the end means you can add a
new input later without editing this line.

```nix
    let
      user = "haotieu";
```

**Change this line if the computer is not mine.** This name becomes
`home.username` and `home.homeDirectory`, and from there it goes into every file
link. Step 4 of `bootstrap.sh` offers to change it for you. It looks for the
exact text `user = "..."`, so keep the spacing if you edit it yourself.

```nix
      system = "x86_64-linux";
```

Which kind of computer to build for. `x86_64-linux` covers every Intel and AMD
PC. Change it to `aarch64-linux` only on an ARM Windows machine, like a
Snapdragon X or Surface Pro X.

```nix
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
```

Loads nixpkgs for our kind of computer.

`allowUnfree` matters because some programs have licences that are not open
source, and nixpkgs refuses to build those unless you say yes first. Nothing
here needs it today. It is set now so that adding such a program later is a
one-line change, instead of a confusing build failure.

We write `import nixpkgs { ... }` rather than the shorter
`nixpkgs.legacyPackages.${system}`. The short form uses default settings, and
there is no way to turn on `allowUnfree` with it.

```nix
      homeConfigurations."wsl" = home-manager.lib.homeManagerConfiguration {
```

The output that the tools look for. When you run
`home-manager switch --flake ~/.dotfiles#wsl`, the `#wsl` part picks this one.
If you rename `"wsl"`, change `#wsl` in `bootstrap.sh` and `rebuild.sh` too.

```nix
        inherit pkgs;
```

Short for `pkgs = pkgs;`. It hands our package set to home-manager.

```nix
        extraSpecialArgs = { inherit user; };
```

Passes `user` down so `home.nix` can use it. That is why `home.nix` starts with
`{ config, pkgs, user, ... }:`. NixOS and nix-darwin call this `specialArgs`;
home-manager adds the `extra` prefix.

```nix
        modules = [ ./home.nix ];
```

The list of setting files. Everything else is in `home.nix`. To split your
setup into more files, add them here.

```nix
      templates = {
        python = { path = ./templates/python; description = "..."; };
        node   = { path = ./templates/node;   description = "..."; };
      };
```

The second output. `templates` is a normal flake feature that
`nix flake init -t` reads. It lets a new project start from a working setup:

```bash
cd ~/my-api
nix flake init -t ~/.dotfiles#python
```

That copies `templates/python/` into the folder you are in. The copy has its own
`flake.lock`, separate from this one. So updating your dotfiles never changes a
project's tool versions. See [11-devshells.md](11-devshells.md).

To see what templates exist, run `nix flake show ~/.dotfiles`.

## Updating versions

```bash
nix flake update                  # update everything, rewrite flake.lock
nix flake update home-manager     # update one thing only
git diff flake.lock               # see exactly what changed
./rebuild.sh                      # apply it
```

**Always commit `flake.lock`.** It is what makes the setup repeatable. Without
it, the next person downloads whatever is newest and can end up with different
packages than you have.

## Common errors

| Message | What it means |
| --- | --- |
| `attribute 'wsl' missing` | The `#wsl` part does not match the name under `homeConfigurations`. |
| `Package ... has an unfree license` | `config.allowUnfree` is not set, or you used `legacyPackages`. |
| `error: flake ... does not provide attribute` | You ran `darwin-rebuild` or `nixos-rebuild` instead of `home-manager`. |
| `experimental Nix feature 'nix-command' is disabled` | Nix was installed some other way. Add `experimental-features = nix-command flakes` to `~/.config/nix/nix.conf`. |
