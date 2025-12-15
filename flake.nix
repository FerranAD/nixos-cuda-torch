{
  description = "Flake for cuda and torch development with uv2nix";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.nixos-cuda.org" 
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" 
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        let

          pkgs = import inputs.nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              # cudaSupport = true;
            };
          };

          python = pkgs.python312;
          workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
            workspaceRoot = ./.;
          };

          overlay = workspace.mkPyprojectOverlay {
            sourcePreference = "wheel";
          };
          editableOverlay = workspace.mkEditablePyprojectOverlay {
            root = "./.";
          };
          customOverlay = self: super: {
            torch = super.torch.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                pkgs.cudaPackages.cudatoolkit
                pkgs.cudaPackages.cudnn
                pkgs.cudaPackages.libcusparse
                pkgs.cudaPackages.libcusparse_lt
                pkgs.cudaPackages.libcufile
                pkgs.cudaPackages.libnvshmem
                pkgs.cudaPackages.nccl
              ];
              autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [ ]) ++ [ "libcuda.so.1" ];
            });
            nvidia-cufile-cu12 = super.nvidia-cufile-cu12.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                pkgs.rdma-core
              ];
            });
            nvidia-nvshmem-cu12 = super.nvidia-nvshmem-cu12.overrideAttrs (old: {
              nativeBuildInputs = old.nativeBuildInputs ++ [
                pkgs.openmpi
                pkgs.pmix
                pkgs.ucx
                pkgs.libfabric
                pkgs.rdma-core
              ];
            });
            nvidia-cusparse-cu12 = super.nvidia-cusparse-cu12.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                pkgs.cudaPackages.libnvjitlink
              ];
            });
            nvidia-cusolver-cu12 = super.nvidia-cusolver-cu12.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
                pkgs.cudaPackages.libnvjitlink
                pkgs.cudaPackages.libcusparse
                pkgs.cudaPackages.libcublas
              ];
            });

          };

          pythonSets =
            (pkgs.callPackage pyproject-nix.build.packages {
              inherit python;
            }).overrideScope
              (
                pkgs.lib.composeManyExtensions [
                  pyproject-build-systems.overlays.wheel
                  overlay
                  customOverlay
                ]
              );

        in
        {
          devShells.default =
            let
              pythonSet = pythonSets.overrideScope editableOverlay;
              virtualenv = pythonSet.mkVirtualEnv "venv" workspace.deps.all;
            in
            pkgs.mkShell {
              packages = [
                virtualenv
                pkgs.uv
                pkgs.ruff
                pkgs.cudaPackages.cudatoolkit
                pkgs.cudaPackages.cudnn
                pkgs.cudaPackages.cuda_nvcc
              ];

              env = {
                UV_NO_SYNC = "1";
                UV_PYTHON = pythonSet.python.interpreter;
                UV_PYTHON_DOWNLOADS = "never";
              };

              shellHook = ''
                export REPO_ROOT=$(git rev-parse --show-toplevel)
                unset PYTHONPATH
              '';
            };

          packages.default = pythonSets.mkVirtualEnv "venv" workspace.deps.default;

        };

    };
}
