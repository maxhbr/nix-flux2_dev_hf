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
          pythonEnv = python.withPackages (ps: with ps; [
            # CUDA-enabled PyTorch wheels and friends
            torch-bin
            torchvision-bin
            einops
            transformers
            safetensors
            fire
            openai
            huggingface-hub
            requests
            bitsandbytes
            diffusers
          ]);
          cudaLibs = [
            cuda.cudatoolkit
            cuda.cudnn
            cuda.libcublas
            cuda.nccl
          ];
          basePackages = [ pythonEnv ] ++ cudaLibs ++ [
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
        in
        f {
          inherit pkgs cuda python pythonEnv cudaLibs basePackages ldPath envVars root;
        });
    in
    {
      devShells = forAllSystems ({ pkgs, basePackages, envVars, ... }:
        pkgs.mkShell {
          # CUDA libraries pulled from nix store; python deps provided via pythonEnv.
          packages = basePackages;
          env = envVars;
          shellHook = ''
            echo "CUDA_HOME=$CUDA_HOME"
            echo "Example entry point: python run_flux2_4bit.py"
          '';
        });

      apps = forAllSystems ({ pkgs, basePackages, envVars, ldPath, root, ... }:
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
