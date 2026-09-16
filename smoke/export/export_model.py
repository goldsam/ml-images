#!/usr/bin/env python3
"""Export the simplest possible ONNX model: y = 2x + 1.

Deliberately trivial. The point is to prove that the devcontainer can train
and export with PyTorch, and that the runtime image can execute the result
through ONNX Runtime -- not to do anything interesting numerically.
"""
import argparse
import pathlib

import torch


class Affine(torch.nn.Module):
    """y = 2x + 1, with the weights set rather than learned."""

    def __init__(self) -> None:
        super().__init__()
        self.linear = torch.nn.Linear(4, 4)
        with torch.no_grad():
            self.linear.weight.copy_(torch.eye(4) * 2.0)
            self.linear.bias.copy_(torch.ones(4))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.linear(x)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="model.onnx")
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    model = Affine().eval()
    sample = torch.zeros(1, 4)

    torch.onnx.export(
        model,
        (sample,),
        str(out),
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
        opset_version=17,
    )

    print(f"torch {torch.__version__} (CUDA {torch.version.cuda})")
    print(f"cuda available: {torch.cuda.is_available()}")
    print(f"wrote {out} ({out.stat().st_size} bytes)")

    # Record what the .NET side must reproduce.
    expected = model(torch.tensor([[1.0, 2.0, 3.0, 4.0]])).detach().numpy().tolist()[0]
    print("expected output for [1,2,3,4]: " + ", ".join(f"{v:.1f}" for v in expected))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
