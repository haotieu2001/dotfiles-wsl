{
  description = "python devshell";

  # Pinned independently of the dotfiles flake on purpose: a project's
  # toolchain should not move when you rebuild your dotfiles, and vice versa.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          python312
          uv        # resolves and installs into .venv, far faster than pip
          ruff
        ];

        # uv builds a normal .venv in the project. That is the right split:
        # Nix pins the interpreter and the system libraries around it, uv pins
        # the Python packages in uv.lock. Trying to express every PyPI
        # dependency in Nix is a much bigger job with no payoff here.
        shellHook = ''
          export UV_PYTHON="${pkgs.python312}/bin/python3.12"
          export UV_PYTHON_DOWNLOADS=never   # use the pinned interpreter, don't fetch one
        '';
      };
    };
}
