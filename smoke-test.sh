#!/usr/bin/env bash
# Smoke test for the devcontainer image.
#
#   ./smoke-test.sh --image ghcr.io/goldsam/ml-devcontainer:latest [--gpu]
#
# With --image, re-executes itself inside that image. Without, assumes it is
# already running inside the container under test.
set -euo pipefail

IMAGE=""
TEST_GPU=false
while [ $# -gt 0 ]; do
    case "$1" in
        --image)    IMAGE="${2:?--image needs a value}"; shift 2;;
        --image=*)  IMAGE="${1#*=}"; shift;;
        --gpu|--test-gpu) TEST_GPU=true; shift;;
        -h|--help)  sed -n '2,8p' "$0"; exit 0;;
        *)          echo "unknown argument: $1" >&2; exit 2;;
    esac
done

if [ -n "$IMAGE" ]; then
    RUN_ARGS=(--rm -v "$(realpath "$0")":/tmp/smoke-test.sh:ro --entrypoint bash)
    $TEST_GPU && RUN_ARGS+=(--gpus all)
    INNER=()
    $TEST_GPU && INNER=(--gpu)
    exec docker run "${RUN_ARGS[@]}" "$IMAGE" /tmp/smoke-test.sh "${INNER[@]}"
fi

fail() { echo "ERROR: $*" >&2; exit 1; }
ok()   { echo "  OK: $*"; }

echo "=== ml-devcontainer smoke test ==="

echo "[python]"
python3 -c 'import sys; assert sys.version_info >= (3,14), sys.version' || fail "python too old"
ok "$(python3 --version)"

echo "[torch]"
python3 -c 'import torch; print(torch.__version__)' >/dev/null || fail "torch import failed"
ok "torch $(python3 -c 'import torch; print(torch.__version__)')"

# Regression guard: ml-libs used to install a CUDA stack implicitly (via
# stable-baselines3 -> PyPI torch) and gpu-ml/azure-ml then installed a second,
# different one on top. Both shipped. Assert there is exactly one.
echo "[single CUDA stack]"
CUDNN=$(python3 -m pip list --disable-pip-version-check --format=freeze 2>/dev/null \
        | grep -ciE '^nvidia[-_]cudnn' || true)
[ "$CUDNN" -le 1 ] || fail "found $CUDNN cudnn distributions - duplicate CUDA stack regression"
MAJORS=$(python3 -m pip list --disable-pip-version-check --format=freeze 2>/dev/null \
         | grep -oiE '^nvidia[-_][a-z0-9_-]*cu[0-9]+' | grep -oE 'cu[0-9]+$' | sort -u | tr '\n' ' ')
[ "$(echo "$MAJORS" | wc -w)" -le 1 ] || fail "multiple CUDA majors present: $MAJORS"
ok "one CUDA stack (${MAJORS:-none})"

echo "[constraints pin]"
[ -f /opt/torch-constraints.txt ] || fail "/opt/torch-constraints.txt missing"
[ "${PIP_CONSTRAINT:-}" = "/opt/torch-constraints.txt" ] || fail "PIP_CONSTRAINT not set"
ok "torch pinned via PIP_CONSTRAINT"

if $TEST_GPU; then
    echo "[cuda runtime]"
    AVAIL=$(python3 -c 'import torch; print(torch.cuda.is_available())')
    if [ "$AVAIL" = "True" ]; then
        ok "CUDA $(python3 -c 'import torch; print(torch.version.cuda)'), $(python3 -c 'import torch; print(torch.cuda.device_count())') device(s)"
    else
        echo "  WARN: no GPU visible (run with --gpus all on a GPU host)"
    fi
fi

echo "[ml packages]"
python3 -c 'import numpy, pandas, scipy, sklearn, pydantic, typer' || fail "core ML imports failed"
python3 -c 'import gymnasium, stable_baselines3' || fail "RL imports failed"
python3 -c 'import transformers, datasets' || fail "gpu-ml imports failed"
python3 -c 'import matplotlib, mypy' || fail "dev tool imports failed"
ok "core, RL, transformers, dev tools"

echo "[pip metadata preserved]"
for p in numpy pandas torch; do
    python3 -m pip show "$p" >/dev/null 2>&1 || fail "pip cannot see $p metadata"
done
ok "pip can resolve installed packages"

echo "[tooling]"
docker --version >/dev/null || fail "docker CLI missing"
docker buildx version >/dev/null || fail "buildx plugin missing"
docker compose version >/dev/null || fail "compose plugin missing"
dotnet --version >/dev/null || fail ".NET SDK missing"
jupyter --version >/dev/null || fail "jupyter missing"
gh --version >/dev/null || fail "gh missing"
ok "docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1), buildx, compose, dotnet $(dotnet --version), jupyter, gh"

echo "[user]"
[ "$(id -un)" = "vscode" ] || fail "expected to run as vscode, got $(id -un)"
sudo -n true 2>/dev/null || fail "vscode lacks passwordless sudo"
ok "running as vscode with sudo"

echo "=== all smoke tests passed ==="
