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

# Regression guard. CUDA must come from the system only -- PyTorch is installed
# with --no-deps precisely so it does not bring a private copy in site-packages.
# If nvidia-* wheels reappear, the image has two CUDA stacks again.
echo "[single CUDA stack]"
WHEELS=$(python3 -m pip list --disable-pip-version-check --format=freeze 2>/dev/null \
         | grep -ciE '^(nvidia[-_]|cuda[-_]toolkit)' || true)
[ "$WHEELS" -eq 0 ] || fail "$WHEELS nvidia-* pip packages present - CUDA is duplicated in site-packages"
CUDART=$(ls /usr/local/cuda/lib64/libcudart.so.* 2>/dev/null | head -1)
[ -n "$CUDART" ] || CUDART=$(ldconfig -p 2>/dev/null | grep -oE '/[^ ]*libcudart\.so\.[0-9]+' | head -1)
[ -n "$CUDART" ] || fail "system CUDA runtime missing"
ok "CUDA is system-only ($(basename "$CUDART"), 0 nvidia wheels)"

# The whole design depends on torch resolving every symbol against system CUDA.
echo "[torch links system CUDA]"
TORCH_LIB=$(python3 -c 'import torch,os;print(os.path.join(os.path.dirname(torch.__file__),"lib","libtorch_cuda.so"))')
if command -v ldd >/dev/null 2>&1 && [ -f "$TORCH_LIB" ]; then
    MISSING=$(ldd "$TORCH_LIB" 2>/dev/null | grep -c "not found" || true)
    [ "$MISSING" -eq 0 ] || fail "$MISSING unresolved libs in libtorch_cuda.so: $(ldd "$TORCH_LIB" | grep 'not found' | tr -s ' ')"
    ok "libtorch_cuda.so fully resolved against system CUDA"
else
    echo "  SKIP: ldd unavailable"
fi

echo "[onnxruntime]"
python3 -c '
import onnxruntime as ort, sys
p = ort.get_available_providers()
print("  ORT", ort.__version__, "providers:", ", ".join(p))
sys.exit(0 if "CUDAExecutionProvider" in p else 1)
' || fail "ONNX Runtime does not offer CUDAExecutionProvider"
ok "ONNX Runtime present with CUDA provider"

# The guard is torch's metadata, not a constraints file: if torch still declares
# Requires-Dist on the CUDA wheels, the next `pip install` reinstates the whole
# duplicate stack. Assert the declaration is actually gone.
echo "[torch metadata declares no CUDA wheels]"
python3 - <<'PYEOF' || fail "torch still declares CUDA wheel dependencies"
import importlib.metadata as md, re, sys
reqs = md.distribution("torch").requires or []
bad = [r for r in reqs
       if re.match(r"^(nvidia[-_]|cuda[-_](toolkit|bindings|pathfinder))", r, re.I)]
print("  torch Requires-Dist CUDA entries:", len(bad))
for r in bad:
    print("   ", r)
sys.exit(1 if bad else 0)
PYEOF
ok "torch declares no CUDA wheel dependencies"

# Prove the guard holds under the operation that used to break it.
echo "[installing a torch-dependent package adds no CUDA wheels]"
PLAN=$(python3 -m pip install --dry-run --quiet --disable-pip-version-check \
        --report /dev/stdout "stable-baselines3" 2>/dev/null \
       | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); raise SystemExit
import re
print(" ".join(p["metadata"]["name"] for p in d.get("install",[])
      if re.match(r"^(nvidia[-_]|cuda[-_](toolkit|bindings|pathfinder))",p["metadata"]["name"],re.I)))' )
[ -z "$PLAN" ] || fail "installing stable-baselines3 would pull CUDA wheels: $PLAN"
ok "no CUDA wheels pulled by a torch-dependent install"

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
python3 -c 'import onnx, onnxscript' || fail "onnx export toolchain missing"
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
garage --version >/dev/null 2>&1 || fail "garage CLI missing"
aws --version >/dev/null 2>&1 || fail "aws CLI missing"
# presign is a fully offline exercise of the s3 model, endpoint resolution and
# sigv4 -- it catches a botched install without needing a live S3 endpoint.
AWS_ACCESS_KEY_ID=smoke AWS_SECRET_ACCESS_KEY=smoke AWS_DEFAULT_REGION=garage \
    aws s3 presign s3://bucket/key --endpoint-url http://garage:3900 >/dev/null 2>&1 \
    || fail "aws s3 is unusable"
# Needs groff on PATH, which nothing else in the image graph installs.
aws s3 cp help >/dev/null 2>&1 || fail "aws help cannot render -- is groff-base installed?"
jupyter --version >/dev/null || fail "jupyter missing"
gh --version >/dev/null || fail "gh missing"
# Round-trip a member through an archive rather than just --version.
AR_DIR=$(mktemp -d)
echo smoke > "$AR_DIR/member"
(cd "$AR_DIR" && ar rc smoke.a member && [ "$(ar t smoke.a)" = member ] && [ "$(ar p smoke.a member)" = smoke ]) \
    || fail "ar cannot create and read an archive -- is binutils installed?"
rm -rf "$AR_DIR"
git lfs version >/dev/null 2>&1 || fail "git-lfs missing"
# Commit a tracked file and require the blob to be an LFS pointer: proves the
# clean filter is registered for this (non-root) user, not just installed.
LFS_DIR=$(mktemp -d)
(cd "$LFS_DIR" && git init -q && git lfs track '*.bin' >/dev/null \
    && head -c 1024 /dev/urandom > blob.bin && git add .gitattributes blob.bin \
    && git -c user.name=smoke -c user.email=smoke@localhost commit -qm smoke \
    && git cat-file -p HEAD:blob.bin | grep -q '^version https://git-lfs') \
    || fail "git-lfs filters are not active -- was 'git lfs install --system' run?"
rm -rf "$LFS_DIR"
ok "docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1), buildx, compose, dotnet $(dotnet --version), jupyter, gh, ar, git-lfs $(git lfs version | grep -oE '[0-9]+\.[0-9.]+' | head -1), garage $(garage --version | grep -oE 'v[0-9.]+' | head -1), aws $(aws --version | grep -oE '[0-9]+\.[0-9.]+' | head -1)"

echo "[session manager plugin]"
session-manager-plugin --version >/dev/null 2>&1 || fail "session-manager-plugin missing"
# `aws ssm start-session` calls the StartSession API first and only then looks
# for the plugin, so a bare --version check would not prove the CLI can find
# it. Answer StartSession from a local stub instead: the CLI must hand the
# session to the plugin, which announces it before failing to reach the fake
# StreamUrl (it then retries, hence the timeout). A missing plugin shows up as
# "SessionManagerPlugin is not found" instead.
SSM_PORT_FILE=$(mktemp)
python3 - "$SSM_PORT_FILE" <<'PY' &
import http.server, json, sys
class StartSession(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.dumps({"SessionId": "smoke-0", "TokenValue": "smoke",
                           "StreamUrl": "ws://127.0.0.1:1/smoke"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/x-amz-json-1.1")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass
server = http.server.HTTPServer(("127.0.0.1", 0), StartSession)
open(sys.argv[1], "w").write(str(server.server_port))
server.serve_forever()
PY
SSM_STUB_PID=$!
for _ in $(seq 50); do [ -s "$SSM_PORT_FILE" ] && break; sleep 0.1; done
[ -s "$SSM_PORT_FILE" ] || fail "StartSession stub did not start"
SSM_OUT=$(AWS_ACCESS_KEY_ID=smoke AWS_SECRET_ACCESS_KEY=smoke AWS_DEFAULT_REGION=us-east-1 \
    timeout 10 aws ssm start-session --target i-0 \
        --endpoint-url "http://127.0.0.1:$(cat "$SSM_PORT_FILE")" </dev/null 2>&1 || true)
kill "$SSM_STUB_PID" 2>/dev/null || true
rm -f "$SSM_PORT_FILE"
grep -q "Starting session with SessionId: smoke-0" <<<"$SSM_OUT" \
    || fail "aws ssm start-session did not reach the plugin: $SSM_OUT"
ok "session-manager-plugin $(session-manager-plugin --version), reachable from aws ssm start-session"

echo "[postgres client]"
psql --version >/dev/null 2>&1 || fail "psql missing"
for b in pg_dump pg_restore pg_isready; do
    command -v "$b" >/dev/null 2>&1 || fail "$b missing"
done
# Ubuntu's own postgresql-client is 16, and pg_dump refuses to read a server
# newer than itself -- so guard that the client really came from PGDG.
PG_MAJOR=$(psql --version | grep -oE '[0-9]+' | head -1)
[ "${PG_MAJOR:-0}" -ge 17 ] || fail "psql is $PG_MAJOR; expected 17+ from apt.postgresql.org, not Ubuntu's 16"
# Offline exercise of libpq, in the spirit of `aws s3 presign`: connecting to a
# closed local port must reach the "no response" verdict (exit 2) rather than
# failing to start. A missing/mislinked libpq.so shows up as 127 or 3 instead.
PG_RC=0
pg_isready -q -h 127.0.0.1 -p 1 -t 2 >/dev/null 2>&1 || PG_RC=$?
[ "$PG_RC" -eq 2 ] || fail "pg_isready against a closed port returned $PG_RC, expected 2 (no response)"
ok "psql $(psql --version | awk '{print $3}') with pg_dump/pg_restore/pg_isready, libpq usable"

# Projects must be able to make their own environment without reinstalling the
# multi-GB CUDA stack. This only works if the image installs into the BASE
# interpreter -- a venv cannot inherit another venv's site-packages.
echo "[project venv can inherit the image stack]"
TMPV=$(mktemp -d)
python3 -m venv --system-site-packages "$TMPV/proj" 2>/dev/null || fail "venv creation failed"
"$TMPV/proj/bin/python" -c 'import torch, onnxruntime' 2>/dev/null \
    || fail "project venv cannot see the image's torch/onnxruntime"
"$TMPV/proj/bin/python" -m pip install -q --disable-pip-version-check tabulate 2>/dev/null
"$TMPV/proj/bin/python" -c 'import tabulate' 2>/dev/null || fail "project venv cannot install its own packages"
python3 -c 'import importlib.util,sys; sys.exit(0 if importlib.util.find_spec("tabulate") is None else 1)' \
    || fail "project install leaked into the image interpreter"
rm -rf "$TMPV"
ok "project venv inherits torch/ORT and installs its own deps in isolation"

echo "[uv]"
uv --version >/dev/null 2>&1 || fail "uv not installed"
ok "uv $(uv --version | awk '{print $2}')"

echo "[user]"
[ "$(id -un)" = "vscode" ] || fail "expected to run as vscode, got $(id -un)"
sudo -n true 2>/dev/null || fail "vscode lacks passwordless sudo"
ok "running as vscode with sudo"

echo "=== all smoke tests passed ==="
