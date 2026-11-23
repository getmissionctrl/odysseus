# Nix flake for Odysseus

Packages, a dev shell, and NixOS / nix-darwin service modules for Odysseus.
Based on Collin Diekvoss's (ToyVo) Nix stack proposed upstream in
odysseus-dev/odysseus#2567 and #2568, rebased onto current `dev`.

| Output | What it is |
|---|---|
| `packages.<system>.default` | The app: Python env from `requirements.txt` + `odysseus`, `odysseus-setup`, `odysseus-chroma` wrappers |
| `packages.<system>.odysseus-extras` | Same, plus optional features: PyMuPDF, ddgs, markitdown, RapidOCR, psd-tools |
| `nixosModules.default` | `services.odysseus`: systemd units for the app and ChromaDB, optional SearXNG, llama.cpp, Chromium |
| `darwinModules.default` | The same on nix-darwin (launchd) |
| `devShells.<system>.default` | Editable dev environment (`nix develop`) |
| `overlays.default` | The Python overrides below |

Systems: `x86_64-linux`, `aarch64-linux` (without FastEmbed, which nixpkgs marks
broken there), `aarch64-darwin`. Intel macOS is not supported by nixos-unstable.

## Deploying on NixOS

```nix
# flake.nix of the host
inputs.odysseus.url = "github:getmissionctrl/odysseus/nix";

# configuration
{ inputs, pkgs, ... }:
{
  imports = [ inputs.odysseus.nixosModules.default ];

  services.odysseus = {
    enable = true;
    port = 7000;
    openFirewall = true;                         # or keep it behind Tailscale / a reverse proxy
    environmentFile = "/run/secrets/odysseus.env";
    searxng = {
      enable = true;                             # web search + Deep Research
      secretKey = "…";                           # must differ from the default; lands in the store
    };
    browser.enable = true;                       # Chromium for the Browser MCP tools
    llamaCpp = {
      enable = true;                             # llama-server for Cookbook GGUF serving
      package = pkgs.llama-cpp.override { cudaSupport = true; };  # needs allowUnfree
    };
  };
}
```

`/run/secrets/odysseus.env` (not world-readable; sops-nix / agenix work well):

```sh
ODYSSEUS_ADMIN_USER=ben
ODYSSEUS_ADMIN_PASSWORD=<8+ characters>
# Where Ollama / an OpenAI-compatible server lives (Ollama's :11434 is also
# used for embeddings when it answers; otherwise FastEmbed runs locally):
LLM_HOST=localhost
```

If no admin password is supplied, first start generates one:
`journalctl -u odysseus | grep "Temporary password"`.

Data lives in `/var/lib/odysseus` (`dataDir`). The first start downloads the
FastEmbed model (all-MiniLM-L6-v2, ~90 MB) into `data/fastembed_cache` unless an
embedding endpoint answers.

### Which nixpkgs builds the app

By default (`services.odysseus.useFlakeNixpkgs = true`) the app is built from
**this flake's locked nixpkgs**, not the host's, so a host on nixos-26.05 still
runs the exact Python closure that was tested. Set it to `false` to build against
the host's nixpkgs instead. SearXNG, Chromium, llama.cpp and the service tools
always come from the host.

## Python overrides (`nix/overlay.nix`)

The flake tracks nixos-unstable because upstream's runtime is Python 3.14 and
`requirements.txt` sets minimums (pydantic, certifi, grpcio, Pillow) that
nixos-26.05 doesn't meet. Two packages are overridden:

- `mcp` pinned to 1.30.0: upstream requires `mcp<2` (built-in MCP servers use
  SDK v1), unstable ships 2.x.
- `fastembed` bumped to 0.9.1: upstream requires it for Pillow 13; nixpkgs has 0.8.0.
- `psd-tools` (optional `psd` extra): one Pillow 13 test deselected. nixpkgs'
  1.12.2 is far behind upstream (1.27), so 1-bit bitmap PSD previews may fail.

## Known limitations

- The Cookbook's "pip install" buttons can't write to the Nix store. Add those
  packages with `services.odysseus.extraPythonPackages = ps: [ ps.… ];`.
- `nix flake check` includes a NixOS VM test (`checks.x86_64-linux.nixos-module`)
  that needs KVM.

## Keeping up with upstream

The `nix` branch only adds files (`flake.nix`, `flake.lock`, `default.nix`,
`nix/`), so it rebases onto upstream `dev` without conflicts:

```sh
git fetch https://github.com/odysseus-dev/odysseus dev
git rebase FETCH_HEAD          # on the nix branch
nix flake update nixpkgs       # optional: move to a newer nixos-unstable
nix build .#default && nix flake check
```

Python dependencies are read from `requirements.txt` at evaluation time, so new
upstream deps are picked up automatically; one that isn't in nixpkgs fails
evaluation with its name and goes into the overlay or `skipPackages` in
`nix/odysseus.nix`.
