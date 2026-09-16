# End-to-end smoke test

Proves the two images do the job they exist for: that a model exported with
PyTorch in the development image runs under ONNX Runtime in the deployment
image, and that both find CUDA.

| stage | image | does |
|---|---|---|
| 1 | `ml-devcontainer` | `export/export_model.py` exports `y = 2x + 1` to ONNX with PyTorch; `dotnet publish` builds the C# consumer |
| 2 | `ml-dotnet-runtime` | the published consumer loads the model and verifies the output |

The model is deliberately trivial. What is being tested is the plumbing —
PyTorch, the .NET SDK, ONNX Runtime and CUDA all present in the right images —
not anything numerical.

```bash
./smoke/run.sh                 # CPU execution provider
./smoke/run.sh --gpu           # require the CUDA execution provider
./smoke/run.sh --dev IMAGE --runtime IMAGE
```

Without `--gpu` the consumer falls back to CPU if the CUDA provider is
unavailable, so the test is meaningful on a machine with no GPU. With `--gpu`
(`REQUIRE_GPU=1`) a missing CUDA provider is a failure.
