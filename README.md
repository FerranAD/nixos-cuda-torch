# CUDA + PyTorch + uv (Nix flake template)

Minimal template for Python projects that need CUDA and PyTorch, using `uv` for dependency management. Just run:

```sh
nix develop --accept-flake-config
```

## Using a different python version
This project uses python 3.12 by default. To use a different python version, edit the `python` input in `flake.nix` to your desired version, e.g., `python39`, `python310`, etc. Then edit `.python-version` and `pyproject.toml` to match the same version and run `uv sync` to generate new lock files.
