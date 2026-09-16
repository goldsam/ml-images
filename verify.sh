#!/usr/bin/env bash
# Build every image, then verify it.
#
#   ./verify.sh          # CPU is acceptable
#   ./verify.sh --gpu    # require the CUDA execution provider
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

GPU=()
[ "${1:-}" = "--gpu" ] && GPU=(--gpu)

mkdir -p .buildx-cache
export CACHE_PATH="$PWD/.buildx-cache"

echo "=== 1/3  build ==="
docker buildx bake --allow=fs="$CACHE_PATH" -f docker-bake.hcl --load all

IMAGE=$(docker buildx bake -f docker-bake.hcl --print devcontainer \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["target"]["devcontainer"]["tags"][0])')

echo "=== 2/3  image smoke test ==="
./smoke-test.sh --image "$IMAGE" "${GPU[@]}"

echo "=== 3/3  end-to-end: export in devcontainer, run in runtime ==="
./smoke/run.sh "${GPU[@]}"

echo "=== PIPELINE PASSED ==="
