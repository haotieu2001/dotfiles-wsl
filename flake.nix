{
  description = "dotfiles for WSL Ubuntu";

  inputs = {
    # Linux release branch. The macOS original uses `nixpkgs-26.05-darwin`;
    # that branch only builds Darwin packages, so on WSL we track `nixos-26.05`.
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
        # Lets us install packages with non-free licenses, e.g. claude-code.
        config.allowUnfree = true;
      };
    in
    {
      # `home-manager switch --flake ~/.dotfiles#wsl` targets this attribute.
      # The macOS original calls its equivalent "mac"; if you rename "wsl",
      # rename it in bootstrap.sh and rebuild.sh too.
      homeConfigurations."wsl" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit user; };
        modules = [ ./home.nix ];
      };
    };
}
