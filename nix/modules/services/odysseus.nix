# NixOS and nix-darwin service modules for Odysseus.
#
# `src` is the repo root, passed by the flake so package builds resolve it
# from this nested module file. `pinnedPkgsFor` (system -> pkgs) is the
# flake's own locked nixpkgs with the Odysseus overlay applied; null when the
# modules are imported without the flake. Exposes { nixosModule, darwinModule }.
{
  src,
  pinnedPkgsFor ? null,
}:
{
  nixosModule = import ./nixos.nix { inherit src pinnedPkgsFor; };
  darwinModule = import ./darwin.nix { inherit src pinnedPkgsFor; };
}
