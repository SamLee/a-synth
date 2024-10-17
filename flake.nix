{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      perSystem = { config, pkgs, ... }: rec {
        formatter = pkgs.nixfmt;

        packages = rec {
          default = pkgs.stdenv.mkDerivation {
            name = "zig-clap";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ pkgs.zig ];
          };

          devShells.default = with pkgs;
            mkShell {
              packages = [ ];
              inputsFrom = [ packages ];
            };
        };
      };
    };
}
