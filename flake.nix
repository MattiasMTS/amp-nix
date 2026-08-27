{
  description = "Always up-to-date Nix package for Amp, the agentic coding agent from Sourcegraph";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      overlay = final: prev: {
        amp-cli = final.callPackage ./package.nix { };
        amp = final.amp-cli;
      };
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
          config.allowUnfree = true;
        };
      in
      {
        packages = {
          default = pkgs.amp-cli;
          amp-cli = pkgs.amp-cli;
          amp = pkgs.amp-cli;
        };

        apps = {
          default = {
            type = "app";
            program = "${pkgs.amp-cli}/bin/amp";
          };
          amp = {
            type = "app";
            program = "${pkgs.amp-cli}/bin/amp";
          };
        };

        checks.default = pkgs.amp-cli;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            curl
            gh
            jq
            nixfmt-rfc-style
          ];
        };
      }
    )
    // {
      overlays.default = overlay;
    };
}
