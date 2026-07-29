{
  description = "dotfiles for WSL Ubuntu";

  inputs = {
    # The Linux release branch is called `nixos-<release>` even though nothing
    # here runs NixOS; the `-darwin` branches only build macOS packages.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # No nix-darwin and no nix-homebrew here. WSL Ubuntu is not NixOS, so there
    # is no system-level Nix module to hook into: home-manager runs standalone
    # and owns everything under $HOME. See docs/01-flake-nix.md.
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      # The one username line to change if this isn't your machine.
      # bootstrap.sh offers to rewrite this for you if your WSL username differs.
      user = "haotieu";

      # "x86_64-linux" covers every Intel/AMD PC. Change to "aarch64-linux"
      # only on a Windows-on-ARM machine (Snapdragon X, Surface Pro X).
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        # Lets us install packages with non-free licenses. Nothing in the
        # current set needs it; kept so adding one later is a one-line change.
        config.allowUnfree = true;
      };
    in
    {
      # `home-manager switch --flake ~/.dotfiles#wsl` targets this attribute.
      # If you rename "wsl", rename it in bootstrap.sh and rebuild.sh too.
      homeConfigurations."wsl" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit user; };
        modules = [ ./home.nix ];
      };

      # Starting points for per-project devshells:
      #     nix flake init -t ~/.dotfiles#python
      #
      # This config owns $HOME, not your projects. A project's toolchain
      # belongs in that project, pinned by its own flake.lock, so it travels
      # with the repo instead of living on one laptop. See docs/11-devshells.md.
      templates = {
        python = {
          path = ./templates/python;
          description = "python 3.12 + uv + ruff devshell";
        };
        node = {
          path = ./templates/node;
          description = "node 24 + pnpm devshell";
        };
      };
    };
}
