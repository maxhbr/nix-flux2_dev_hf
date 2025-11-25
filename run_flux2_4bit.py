"""
Run the FLUX.2 4-bit quantized pipeline with CPU offload (fits ~20G VRAM).

Requires Hugging Face login (`hf auth login`) and internet access to pull weights.
"""

import argparse
from pathlib import Path

import torch
from diffusers import Flux2Pipeline, Flux2Transformer2DModel
from transformers import Mistral3ForConditionalGeneration


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run FLUX.2 4-bit pipeline")
    parser.add_argument(
        "--prompt",
        default=(
            "Realistic macro photograph of a hermit crab using a soda can as its shell, "
            "partially emerging from the can, captured with sharp detail and natural "
            "colors, on a sunlit beach with soft shadows and a shallow depth of field, "
            "with blurred ocean waves in the background. The can has the text "
            "`BFL + Diffusers` on it and it has a color gradient that start with "
            "#FF5733 at the top and transitions to #33FF57 at the bottom."
        ),
        help="Text prompt to generate",
    )
    parser.add_argument("--repo-id", default="diffusers/FLUX.2-dev-bnb-4bit", help="Model repo id")
    parser.add_argument("--device", default="cuda:0", help="CUDA device string")
    parser.add_argument("--steps", type=int, default=50, help="Number of inference steps")
    parser.add_argument("--guidance", type=float, default=4.0, help="Classifier-free guidance scale")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("flux2_output.png"),
        help="Where to save the generated image",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    device = args.device
    torch_dtype = torch.bfloat16

    transformer = Flux2Transformer2DModel.from_pretrained(
        args.repo_id, subfolder="transformer", torch_dtype=torch_dtype, device_map="cpu"
    )
    text_encoder = Mistral3ForConditionalGeneration.from_pretrained(
        args.repo_id, subfolder="text_encoder", dtype=torch_dtype, device_map="cpu"
    )

    pipe = Flux2Pipeline.from_pretrained(
        args.repo_id, transformer=transformer, text_encoder=text_encoder, torch_dtype=torch_dtype
    )
    pipe.enable_model_cpu_offload()

    generator = torch.Generator(device=device).manual_seed(args.seed)
    image = pipe(
        prompt=args.prompt,
        generator=generator,
        num_inference_steps=args.steps,
        guidance_scale=args.guidance,
    ).images[0]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output)
    print(f"Saved image to {args.output}")


if __name__ == "__main__":
    main()
