{
  description = "Odysseus AI Workspace Environment";

  # Defines the source of our packages. Tracks nixos-unstable (locked in
  # flake.lock): upstream's Docker image runs Python 3.14 and requirements.txt
  # now sets minimums (pydantic, certifi, grpcio, Pillow) that nixos-26.05
  # does not meet. The two deps unstable gets wrong for Odysseus (mcp, which
  # must stay <2, and fastembed) are pinned in nix/overlay.nix.
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  # Nix code is split out of this file (cf. the native-nix effort in issue #605):
  #   nix/odysseus.nix                    — the main odysseus package (callPackage)
  #   nix/lib.nix                         — mkRuntimeLibs / mkContainer helpers
  #   nix/overlay.nix                     — Python package overrides (pythonPackagesExtensions)
  #   nix/modules/services/odysseus.nix   — the NixOS & nix-darwin service modules
  #                                         (Chroma, SearXNG, firewall, app)
  #   nix/modules/checks/integration.nix  — the integration tests
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-darwin,
      flake-compat ? null,
      ...
    }@inputs:
    let
      inherit (import ./nix/lib.nix) mkContainer mkRuntimeLibs;
      # Standard nixpkgs overlay (Darwin test-skips via pythonPackagesExtensions).
      # Applied here so the package and dev shell see the same overridden
      # interpreter, and exported as overlays.default for downstream
      # NixOS / nix-darwin modules (`nixpkgs.overlays = [ odysseus.overlays.default ]`).
      pythonOverlay = import ./nix/overlay.nix;
      # The flake's own locked nixpkgs (+ overlay) for a given system. The
      # service modules build the app from this by default
      # (services.odysseus.useFlakeNixpkgs) so a deployed host runs exactly
      # the Python closure this flake was tested with, whatever nixpkgs the
      # host itself is on.
      pinnedPkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ pythonOverlay ];
        };
      odysseusModules = import ./nix/modules/services/odysseus.nix {
        src = ./.;
        inherit pinnedPkgsFor;
      };
    in
    # x86_64-darwin is omitted: nixpkgs dropped Intel macOS after 26.05
    # (see the 26.11 release notes), so nixos-unstable can't evaluate it.
    (flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = pinnedPkgsFor system;
          # Default app package (no extra packages); uses callPackage.
          odysseus = pkgs.callPackage ./nix/odysseus.nix {
            src = ./.;
            extraPythonPackages = _ps: [ ];
          };
          # Same package with every optional feature from requirements-optional.txt
          # enabled (PyMuPDF, ddgs, markitdown, RapidOCR, psd-tools). Build with
          # `nix build .#odysseus-extras`; for a subset, override `extras`:
          #   odysseus.override { extras = [ "pdf" "ocr" ]; }
          odysseus-extras = odysseus.override {
            extras = [
              "pdf"
              "ddg"
              "markitdown"
              "ocr"
              "psd"
            ];
          };
          # Helper scripts for the dev shell
          odysseus-setup-wrapper = pkgs.writeShellScriptBin "odysseus-setup-wrapper" (
            builtins.readFile ./nix/scripts/odysseus-setup-wrapper.sh
          );
          odysseus-run-tmux = pkgs.writeShellScriptBin "odysseus-run-tmux" (
            builtins.readFile ./nix/scripts/odysseus-run-tmux.sh
          );
          odysseus-cache-npx = pkgs.writeShellScriptBin "odysseus-cache-npx" (
            builtins.readFile ./nix/scripts/odysseus-cache-npx.sh
          );
        in
        {
          # The dev shell is defined in nix/shell.nix so it
          # also works via a bare `nix-shell nix/shell.nix`. Pass the flake's
          # pinned pkgs so `nix develop` uses the locked nixpkgs.
          devShells.default = import ./nix/shell.nix {
            inherit pkgs;
            extraInputs = [
              odysseus-setup-wrapper
              odysseus-run-tmux
              odysseus-cache-npx
            ];
          };

          packages = {
            default = odysseus;
            odysseus = odysseus;
            odysseus-extras = odysseus-extras;
            container = mkContainer pkgs odysseus;
          };
        }
      )
    )
    // {
      # System-independent: usable by downstream NixOS / nix-darwin configs.
      overlays.default = pythonOverlay;
      nixosModules.default = odysseusModules.nixosModule;
      darwinModules.default = odysseusModules.darwinModule;
      checks = import ./nix/modules/checks/integration.nix {
        inherit
          self
          nixpkgs
          nix-darwin
          mkRuntimeLibs
          ;
      };
    };
}
