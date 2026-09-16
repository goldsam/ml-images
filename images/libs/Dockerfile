# Python ML stack. PyTorch and ONNX Runtime, both bound to the system CUDA
# provided by cuda-base -- neither brings its own.
FROM cuda-base-image

ARG PYTHON_VERSION=3.14
ARG UV_VERSION=0.12.15
ARG TORCH_CUDA=cu126
ARG TORCH_VERSION=

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /workspace

# Layer 1: Python. Ubuntu 24.04 ships 3.12; deadsnakes supplies newer, and
# unlike Ubuntu's own python3 it carries no EXTERNALLY-MANAGED marker -- which
# matters, because this image installs into the BASE interpreter (see below).
# uv's own managed Pythons are NOT usable here: uv marks them externally
# managed ("managed by uv and should not be modified"), so packages cannot be
# installed into their site-packages. uv is still installed, for projects.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists \
    set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        "python${PYTHON_VERSION}" \
        "python${PYTHON_VERSION}-venv"

# Install into the BASE interpreter, not a venv. A venv inside a venv does not
# chain: `python -m venv --system-site-packages` exposes the base interpreter's
# site-packages only, so a project venv could not inherit a venv-based stack and
# would reinstall torch -- reintroducing the multi-GB duplicate CUDA this image
# exists to avoid. deadsnakes ships no EXTERNALLY-MANAGED marker, so pip can
# install here without --break-system-packages.
ENV PYTHON=python${PYTHON_VERSION}
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-bootstrap \
    set -ex \
    && "python${PYTHON_VERSION}" -m ensurepip --altinstall \
    && "python${PYTHON_VERSION}" -m pip install --no-cache-dir -U pip setuptools wheel \
    && update-alternatives --install /usr/local/bin/python3 python3 "/usr/bin/python${PYTHON_VERSION}" 1 \
    && ln -sf /usr/local/bin/python3 /usr/local/bin/python

# Layer 2: CUDA libraries PyTorch needs that the -cudnn-runtime base omits.
#   cuda-cupti-12-9  -> libcupti.so.12        (CUPTI ships in -devel only)
#   libcusparselt0   -> libcusparseLt.so.0    (separate NVIDIA product)
#   nvshmem-cuda-12  -> libnvshmem_host.so.3  (the meta-package; libnvshmem3-cuda-12
#                        alone installs the lib but not the alternatives symlink)
#   libnccl2         -> libnccl.so.2          (UPGRADE, see note below)
# ~350MB, versus the ~3.0GB of pip wheels they replace.
#
# NCCL must be UPGRADED, not merely present. The 12.9 base ships 2.27.3 but
# torch 2.14 requires >= 2.29.3; under --no-deps the system copy is the only
# one, so the older library fails at import with
#   undefined symbol: ncclCommGrow
# The package is apt-held, hence --allow-change-held-packages. The version is
# selected from the cuda12 flavours explicitly -- plain `libnccl2` resolves to
# the newest across ALL flavours, which is a +cuda13 build on a CUDA 12 base.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists \
    set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends --allow-change-held-packages \
        cuda-cupti-12-9 \
        libcusparselt0 \
        nvshmem-cuda-12 \
        "libnccl2=$(apt-cache madison libnccl2 | awk -F'|' '/cuda12/{gsub(/ /,"",$2); print $2; exit}')" \
    && dpkg-query -W -f='NCCL: ${Version}\n' libnccl2

# Layer 3: PyTorch WITHOUT its bundled nvidia-* wheels, so it links the system
# CUDA above. Driven by ARGs with no COPY, so editing requirements.txt does not
# invalidate this layer. torch's pure-Python dependencies are listed explicitly
# because --no-deps skips them too.
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-torch \
    set -ex \
    && python3 -m pip install --disable-pip-version-check --no-compile --no-deps \
        "torch${TORCH_VERSION:+==${TORCH_VERSION}}" \
        --index-url "https://download.pytorch.org/whl/${TORCH_CUDA}" \
    # --no-deps skips ALL of torch's dependencies, not just the CUDA wheels, so
    # the ones we do want are listed explicitly. triton is a genuine pip
    # dependency (the kernel compiler behind torch.compile), not a system lib.
    && python3 -m pip install --disable-pip-version-check --no-compile \
        filelock typing-extensions sympy networkx jinja2 fsspec triton \
    # pip prints a dependency-conflict warning here listing torch's nvidia-*
    # requirements as "not installed". That is the entire point of --no-deps:
    # those libraries come from the image instead. The import check below is
    # what actually proves the result is usable.
    && python3 -c "import torch; print('torch', torch.__version__, 'CUDA', torch.version.cuda)"

# torch's dist-info still declares Requires-Dist on the CUDA wheels we just
# skipped. Any later `pip install` that pulls torch into the resolution graph
# would treat them as missing and reinstall the whole ~3GB stack. Make the
# metadata match reality instead.
COPY unbundle_cuda.py /usr/local/bin/unbundle_cuda.py
RUN python3 /usr/local/bin/unbundle_cuda.py

# uv: projects create their own environment with
#     uv venv --system-site-packages   (inherits this image's torch/ONNX Runtime)
#     uv pip install -e .              (project deps layer on top)
# --torch-backend also stops anyone silently pulling a second CUDA stack.
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-uv \
    python3 -m pip install --disable-pip-version-check "uv==${UV_VERSION}" \
    && uv --version

# Layer 4: the rest of the stack, including ONNX Runtime. Installed without its
# cuda/cudnn extras so it uses the system CUDA too.
COPY requirements.txt /tmp/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-wheels \
    set -ex \
    && python3 -m pip install --disable-pip-version-check --no-compile --prefer-binary \
        -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt \
    && SP="$(python3 -c 'import site;print(site.getsitepackages()[0])')" \
    && find "$SP" -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true \
    && find "$SP" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true \
    && find "$SP" -name "*.pyc" -delete \
    && find "$SP" -name "*.a" -delete \
    && find "$SP" -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true

COPY dedupe.py /usr/local/bin/dedupe.py
RUN python3 /usr/local/bin/dedupe.py "$(python3 -c 'import site;print(site.getsitepackages()[0])')"

ENTRYPOINT ["/usr/bin/tini","--"]
