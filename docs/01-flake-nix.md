# 01 - `flake.nix`

The entry point. A flake is a Nix file with pinned `inputs` and computed
`outputs`; `flake.lock` records the exact git revision of every input, which is
what makes the setup reproducible rather than merely scripted.

## Line by line

```nix
{
  description = "dotfiles for WSL Ubuntu";
```

Free-text label, shown by `nix flake show`. No functional effect.

```nix
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
```

The package set. `nixos-26.05` is the stable release branch; it receives
security and bugfix backports but no version churn, so builds stay predictable.

The video uses `nixpkgs-26.05-darwin`. Branches ending in `-darwin` are built
and cached only for macOS, so on Linux you want `nixos-<release>` even though
you are not running NixOS. Using `nixpkgs-unstable` here instead would track
the rolling branch and give you exactly the "surprises" the video pins against.

```nix
    home-manager.url = "github:nix-community/home-manager/release-26.05";
```

home-manager, on the branch matching nixpkgs. **Keep these two in lockstep.**
A home-manager release expects module options that match its nixpkgs release;
mixing `release-26.05` with `nixos-25.11` produces confusing evaluation errors.

```nix
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
```

Forces home-manager to use *our* nixpkgs rather than pulling a second copy.
Without this you would download and store two full package sets, and could end
up with two different builds of the same library in one profile.

```nix
    # No nix-darwin and no nix-homebrew here.
  };
```

The two inputs the video has that this repo deliberately drops. See
[00-what-changed-from-macos.md](00-what-changed-from-macos.md).

```nix
  outputs = { self, nixpkgs, home-manager, ... }:
```

The function producing the flake's results. The `...` absorbs any input added
later without needing to edit this signature.

```nix
    let
      user = "haotieu";
```

**The one line to change if this is not your machine.** It flows into
`home.username`, `home.homeDirectory`, and therefore into every symlink path.
`bootstrap.sh` step 4 offers to rewrite exactly this line, matching on
`user = "..."`, so keep the formatting if you edit it by hand.

```nix
      system = "x86_64-linux";
```

The build platform. `x86_64-linux` covers every Intel and AMD PC. Change to
`aarch64-linux` only on Windows-on-ARM hardware (Snapdragon X, Surface Pro X).
This replaces the video's `nixpkgs.hostPlatform = "aarch64-darwin"`.

```nix
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
```

Instantiates nixpkgs for our platform. `allowUnfree` is the direct equivalent
of the video's `nixpkgs.config.allowUnfree = true`: nixpkgs refuses to build
non-free-licensed packages unless you opt in, and `claude-code` is one of them.

Note we use `import nixpkgs { ... }` rather than the shorter
`nixpkgs.legacyPackages.${system}`. The short form gives you a package set with
default config, and there is no way to set `allowUnfree` on it.

```nix
      homeConfigurations."wsl" = home-manager.lib.homeManagerConfiguration {
```

The output the tooling looks for. `home-manager switch --flake ~/.dotfiles#wsl`
selects this attribute by the name `wsl`. The video's equivalent is
`darwinConfigurations."mac"`. If you rename `"wsl"`, change the `#wsl` fragment
in both `bootstrap.sh` and `rebuild.sh` too.

```nix
        inherit pkgs;
```

Shorthand for `pkgs = pkgs;`, handing our configured package set to home-manager.

```nix
        extraSpecialArgs = { inherit user; };
```

Makes `user` available as a module argument, which is why `home.nix` can begin
with `{ config, pkgs, user, ... }:`. The video passes the same value through
`specialArgs`; the `extra` prefix is the home-manager spelling.

```nix
        modules = [ ./home.nix ];
```

The module list. Everything else lives in `home.nix`. To split your config
further, add more files here.

## Working with the lock file

```bash
nix flake update                  # bump every input, rewrite flake.lock
nix flake update home-manager     # bump just one
git diff flake.lock               # see exactly what moved
./rebuild.sh                      # apply
```

`flake.lock` is the reproducibility guarantee and **must be committed**. A
missing lock file means the next person resolves branches fresh and can get
different packages than you have.

## Common errors

| Message | Cause |
| --- | --- |
| `attribute 'wsl' missing` | The `#wsl` fragment does not match the `homeConfigurations` name. |
| `Package ... has an unfree license` | `config.allowUnfree` is not set, or you used `legacyPackages`. |
| `error: flake ... does not provide attribute` | Ran `darwin-rebuild` or `nixos-rebuild` instead of `home-manager`. |
| `experimental Nix feature 'nix-command' is disabled` | Nix was installed by something other than the Determinate installer; add `experimental-features = nix-command flakes` to `~/.config/nix/nix.conf`. |
