# Python package overrides for Odysseus.
#
# Exposed as a standard nixpkgs overlay so downstream NixOS / nix-darwin modules
# can apply it via `nixpkgs.overlays = [ odysseus.overlays.default ]` and get the
# same Darwin test-skips the flake uses. Uses `pythonPackagesExtensions`, the
# nixpkgs-recommended mechanism for extending the python package set: it composes
# with other overlays and applies across every python3 interpreter, unlike
# `python3.override { packageOverrides }` which is scoped to one instance.
#
# `final` / `prev` are the top-level nixpkgs scopes; the inner `pyFinal` /
# `pyPrev` are the python package scopes.
final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pyFinal: pyPrev: {
      # niquests' test suite fails on Darwin (notably under nixos-unstable,
      # which consumers pull in via inputs.nixpkgs.follows). Skip it there.
      niquests = pyPrev.niquests.overridePythonAttrs (old: {
        doCheck = !final.stdenv.hostPlatform.isDarwin;
      });

      # caldav's test suite fails on Darwin. Skip its checks there; they pass
      # on Linux / the pinned nixpkgs.
      caldav = pyPrev.caldav.overridePythonAttrs (old: {
        doCheck = !final.stdenv.hostPlatform.isDarwin;
        doInstallCheck = !final.stdenv.hostPlatform.isDarwin;
      });

      # requirements.txt pins `mcp<2` (built-in MCP servers stay on SDK v1,
      # upstream #5820) but nixos-unstable ships mcp 2.x. Pin the last 1.x
      # release, built from the PyPI sdist with the 1.x dependency set
      # (mirrors nixpkgs' own mcp 1.x expression). Tests are skipped: the
      # inherited test inputs/exclusions are for the 2.x suite.
      mcp = pyPrev.mcp.overridePythonAttrs (old: rec {
        version = "1.30.0";
        src = pyFinal.fetchPypi {
          pname = "mcp";
          inherit version;
          hash = "sha256-RFQUYl/OXClfqlBbsRus7OZhq29AKNV8k121eCC3o+Q=";
        };
        dependencies =
          with pyFinal;
          [
            anyio
            httpx
            httpx-sse
            jsonschema
            pydantic
            pydantic-settings
            pyjwt
            python-multipart
            sse-starlette
            starlette
            typing-extensions
            typing-inspection
            uvicorn
          ]
          ++ pyjwt.optional-dependencies.crypto;
        pythonRelaxDeps = [ "pydantic-settings" ];
        doCheck = false;
        nativeCheckInputs = [ ];
        disabledTests = [ ];
        preCheck = "";
        meta = old.meta // {
          changelog = "https://github.com/modelcontextprotocol/python-sdk/releases/tag/v${version}";
        };
      });

      # psd-tools (optional `psd` extra): nixpkgs' 1.12.2 predates Pillow 13
      # and one composite test fails for 1-bit bitmap PSDs ("Invalid mode for
      # data type"). Deselect just that case; bitmap-mode PSD previews may
      # fail at runtime until nixpkgs moves to a current psd-tools.
      psd-tools = pyPrev.psd-tools.overridePythonAttrs (old: {
        pytestFlags = (old.pytestFlags or [ ]) ++ [
          "--deselect=tests/psd_tools/composite/test_composite.py::test_composite_pil[bitmap-1-1-True-False]"
        ];
      });

      # requirements.txt requires fastembed>=0.9.1 (the release compatible
      # with Pillow 13, upstream #6845); nixpkgs is still on 0.8.0.
      fastembed = pyPrev.fastembed.overridePythonAttrs (old: rec {
        version = "0.9.1";
        src = pyFinal.fetchPypi {
          pname = "fastembed";
          inherit version;
          hash = "sha256-i0sogeqFpNNujyhEZmcUN7P+2GnDPNxx1vbEjd/xFcc=";
        };
        # 0.9 moved from poetry-core to uv_build (>=0.13,<0.14).
        build-system = [ pyFinal.uv-build ];
        meta = old.meta // {
          changelog = "https://github.com/qdrant/fastembed/releases/tag/v${version}";
        };
      });
    })
  ];
}
