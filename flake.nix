{
  description = "Nix dev shell for running FLUX.2 4-bit examples on CUDA GPUs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      root = ./.;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          cuda = pkgs.cudaPackages;
          python = pkgs.python311;
          pythonDeps = with python.pkgs; [
            pip
            setuptools
            wheel
            virtualenv
          ];
          cudaLibs = [
            cuda.cudatoolkit
            cuda.cudnn
            cuda.libcublas
            cuda.nccl
          ];
          basePackages = [ python ] ++ pythonDeps ++ cudaLibs ++ [
            pkgs.git
            pkgs.which
            pkgs.stdenv.cc.cc
            pkgs.zlib
          ];
          ldPath = pkgs.lib.makeLibraryPath (cudaLibs ++ [
            pkgs.stdenv.cc.cc
            pkgs.zlib
          ]);
          envVars = {
            CUDA_HOME = "${cuda.cudatoolkit}";
            LD_LIBRARY_PATH = ldPath;
            PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
            HF_HUB_ENABLE_HF_TRANSFER = "1";
          };
          setupVenv = ''
            if [ -w . ]; then
              VENV="${FLUX2_VENV:-.venv}"
            else
              VENV="${FLUX2_VENV:-$HOME/.cache/flux2-venv}"
            fi
            mkdir -p "$(dirname "$VENV")"
            if [ ! -d "$VENV" ]; then
              echo "Creating python venv in $VENV"
              python -m venv "$VENV"
            fi

            # shellcheck disable=SC1090,SC1091
            source "$VENV/bin/activate"

            # Install python deps once. Torch/torchvision pulled from official CUDA wheels.
            if [ ! -f "$VENV/.deps-installed" ]; then
              echo "Installing python deps (torch/cu124, diffusers main, 4-bit stack)..."
              pip install --upgrade pip
              pip install --index-url https://download.pytorch.org/whl/cu124 \
                torch==2.8.0 torchvision==0.23.0
              pip install \
                git+https://github.com/huggingface/diffusers.git \
                transformers==4.56.1 \
                einops==0.8.1 \
                safetensors==0.4.5 \
                fire==0.7.1 \
                openai==2.8.1 \
                huggingface_hub \
                requests \
                bitsandbytes
              touch "$VENV/.deps-installed"
            fi
          '';
        in
        f {
          inherit pkgs cuda python pythonDeps cudaLibs basePackages ldPath envVars setupVenv root;
        });
    in
    {
      devShells = forAllSystems ({ pkgs, basePackages, envVars, setupVenv, ... }:
        pkgs.mkShell {
          # CUDA libraries pulled from nix store; python deps installed via venv/pip in shellHook.
          packages = basePackages;
          env = envVars;
          shellHook = ''
            ${setupVenv}
            echo "CUDA_HOME=$CUDA_HOME"
            echo "Activate env with: source $VENV/bin/activate"
            echo "Example entry point: python run_flux2_4bit.py"
          '';
        });

      apps = forAllSystems ({ pkgs, basePackages, envVars, setupVenv, ldPath, root, ... }:
        let
          runner = pkgs.writeShellApplication {
            name = "flux2-4bit";
            runtimeInputs = basePackages;
            text = ''
              set -euo pipefail
              cd ${root}

              export CUDA_HOME=${envVars.CUDA_HOME}
              export LD_LIBRARY_PATH=${ldPath}
              export PYTORCH_CUDA_ALLOC_CONF=${envVars.PYTORCH_CUDA_ALLOC_CONF}
              export HF_HUB_ENABLE_HF_TRANSFER=${envVars.HF_HUB_ENABLE_HF_TRANSFER}

              ${setupVenv}

              python run_flux2_4bit.py "$@"
            '';
          };
          defaultApp = {
            type = "app";
            program = "${runner}/bin/flux2-4bit";
          };
        in
        {
          default = defaultApp;
          flux2-4bit = defaultApp;
        });
    };
}
