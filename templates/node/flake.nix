{
  description = "node devshell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nodejs_24
          pnpm
        ];

        # node_modules stays a normal npm/pnpm tree. Same split as the python
        # template: Nix pins the runtime, the JS lockfile pins the packages.
        shellHook = ''
          export PATH="$PWD/node_modules/.bin:$PATH"
        '';
      };
    };
}
