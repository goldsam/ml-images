#!/usr/bin/env bash
# End-to-end smoke test across both images.
#
#   1. devcontainer image: PyTorch exports an ONNX model, .NET SDK publishes the consumer
#   2. runtime image:      the published consumer loads the model and verifies the result
#
#   ./smoke/run.sh [--dev IMAGE] [--runtime IMAGE] [--gpu]
set -euo pipefail

DEV_IMAGE="ghcr.io/goldsam/ml-devcontainer:latest"
RUNTIME_IMAGE="ghcr.io/goldsam/ml-dotnet-runtime:latest"
GPU=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dev)       DEV_IMAGE="${2:?--dev needs a value}"; shift 2;;
        --runtime)   RUNTIME_IMAGE="${2:?--runtime needs a value}"; shift 2;;
        --gpu)       GPU=true; shift;;
        -h|--help)   sed -n '2,9p' "$0"; exit 0;;
        *)           echo "unknown argument: $1" >&2; exit 2;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HERE/.out"
rm -rf "$WORK"; mkdir -p "$WORK"

GPU_ARGS=()
$GPU && GPU_ARGS=(--gpus all)

echo "=============================================================="
echo " stage 1/2  build + export   image: $DEV_IMAGE"
echo "=============================================================="
docker run --rm "${GPU_ARGS[@]}" \
    -v "$HERE":/smoke \
    -v "$WORK":/out \
    -w /smoke \
    --entrypoint bash "$DEV_IMAGE" -c '
set -euo pipefail
python3 -m pip install --quiet --disable-pip-version-check onnx onnxscript
echo "--- exporting onnx model with pytorch ---"
python3 export/export_model.py --out /out/model.onnx
echo "--- publishing .NET consumer ---"
dotnet publish consume/OnnxSmoke.csproj \
    -c Release -o /out/app \
    --nologo -v quiet
echo "--- publish output ---"
ls /out/app | head -8
# ONNX Runtime native libraries must be present in the publish output; the image
# supplies CUDA/cuDNN but not ORT itself. They land under runtimes/<rid>/native/,
# not flat in the output directory.
NATIVE=/out/app/runtimes/linux-x64/native
for lib in libonnxruntime.so libonnxruntime_providers_cuda.so; do
    [ -f "$NATIVE/$lib" ] || { echo "ERROR: $lib missing from publish output" >&2; exit 1; }
    echo "  ORT native present: $lib ($(stat -c %s "$NATIVE/$lib") bytes)"
done
'

echo
echo "=============================================================="
echo " stage 2/2  run in runtime    image: $RUNTIME_IMAGE"
echo "=============================================================="
docker run --rm "${GPU_ARGS[@]}" \
    -v "$WORK":/out:ro \
    -w /out \
    -e REQUIRE_GPU="$($GPU && echo 1 || echo 0)" \
    --entrypoint bash "$RUNTIME_IMAGE" -c '
set -euo pipefail
echo "--- runtime image contents ---"
dotnet --list-runtimes | sed "s/^/  /"
echo "  SDKs installed: $(dotnet --list-sdks | wc -l) (expect 0)"
echo "--- running consumer ---"
cd /out/app && exec dotnet OnnxSmoke.dll /out/model.onnx
'

echo
echo "=============================================================="
echo " smoke test PASSED"
echo "=============================================================="
