# amp-nix

Always-fresh Nix package for [Amp](https://ampcode.com), the agentic coding agent from Sourcegraph.

This mirrors the shape of `sadjow/claude-code-nix` and `MattiasMTS/pi-nix`: the flake packages upstream Amp, checks for new versions hourly, updates hashes automatically, builds/tests the result, and opens an auto-merge update PR.

## Why

`nixpkgs` already packages Amp as `amp-cli`, but Amp releases many times per day (versions are build timestamps) and nixpkgs typically lags by weeks. This repository is a small dedicated flake for people who want Amp releases within an hour of publication.

## Usage

Run directly:

```bash
nix run github:MattiasMTS/amp-nix
```

Install to a profile:

```bash
nix profile install github:MattiasMTS/amp-nix
```

Use from another flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    amp-nix = {
      url = "github:MattiasMTS/amp-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

Then add it to Home Manager:

```nix
home.packages = [
  inputs.amp-nix.packages.${pkgs.system}.amp-cli
];
```

## Development

Build and test locally:

```bash
nix build .#amp-cli
./result/bin/amp --version
```

Check for updates:

```bash
./scripts/update.sh --check
```

Update to latest:

```bash
./scripts/update.sh
```

Update to a specific version:

```bash
./scripts/update.sh --version 0.0.1787810366-g2503d7
```

## Automation

GitHub Actions included here:

- `Build`: builds and smoke-tests Amp on Linux and macOS.
- `Update Amp Version`: checks `static.ampcode.com/cli/cli-version.txt` hourly, updates `package.nix` hashes for all platforms, then opens an auto-merge PR.
- `Create Version Tag`: creates immutable `v<version>` tags plus a moving `latest` tag after successful main builds.

For auto-merge to work, enable GitHub repository auto-merge and use branch protection that requires the `Build` check.

## Notes

This package installs the prebuilt Amp binaries published at `static.ampcode.com/cli/<version>/amp-<platform>.gz` (the same artifacts the npm `@ampcode/cli` platform packages wrap). On x86_64-linux the `baseline` build is used so the package works on all supported CPUs. On Darwin the binary's ICU reference is rewritten to the Nix ICU and the binary is re-signed. The wrapper puts `ripgrep` in `PATH` and sets:

- `AMP_SKIP_UPDATE_CHECK=1` because Nix owns the binary version.

Amp itself is unfree software (see [ampcode.com](https://ampcode.com/security)); the flake sets `allowUnfree` for its own package outputs. The Nix packaging code in this repository is MIT licensed.
