# Python ML stack. PyTorch and ONNX Runtime, both bound to the system CUDA
# provided by cuda-base -- neither brings its own.
FROM cuda-base-image

ARG PYTHON_VERSION=3.14
ARG TORCH_CUDA=cu132
ARG TORCH_VERSION=

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /workspace

# Layer 1: Python. Ubuntu 24.04 ships 3.12; deadsnakes supplies newer.
# The venv is not optional -- Ubuntu marks the system interpreter
# externally-managed, so pip refuses to install into it.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists \
    set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        "python${PYTHON_VERSION}" \
        "python${PYTHON_VERSION}-venv" \
    && "python${PYTHON_VERSION}" -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" \
    VIRTUAL_ENV=/opt/venv

# Layer 2: CUDA libraries PyTorch needs that the -cudnn-runtime base omits.
#   cuda-cupti-13-3  -> libcupti.so.13        (CUPTI ships in -devel only)
#   libcusparselt0   -> libcusparseLt.so.0    (separate NVIDIA product)
#   nvshmem-cuda-13  -> libnvshmem_host.so.3  (note: libnvshmem3-cuda-13 does not exist)
# ~350MB, versus the ~3.0GB of pip wheels they replace.
#
# NCCL is deliberately NOT listed: the base already ships libnccl2 2.30.7
# (apt-held at +cuda13.3), which is exactly the version torch wants. Asking for
# it again fails with "Held packages were changed".
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists \
    set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        cuda-cupti-13-3 \
        libcusparselt0 \
        nvshmem-cuda-13

# Layer 3: PyTorch WITHOUT its bundled nvidia-* wheels, so it links the system
# CUDA above. Driven by ARGs with no COPY, so editing requirements.txt does not
# invalidate this layer. torch's pure-Python dependencies are listed explicitly
# because --no-deps skips them too.
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-torch \
    set -ex \
    && pip install --disable-pip-version-check --no-compile --no-deps \
        "torch${TORCH_VERSION:+==${TORCH_VERSION}}" \
        --index-url "https://download.pytorch.org/whl/${TORCH_CUDA}" \
    # --no-deps skips ALL of torch's dependencies, not just the CUDA wheels, so
    # the ones we do want are listed explicitly. triton is a genuine pip
    # dependency (the kernel compiler behind torch.compile), not a system lib.
    && pip install --disable-pip-version-check --no-compile \
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

# Layer 4: the rest of the stack, including ONNX Runtime. Installed without its
# cuda/cudnn extras so it uses the system CUDA too.
COPY requirements.txt /tmp/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-wheels \
    set -ex \
    && pip install --disable-pip-version-check --no-compile --prefer-binary \
        -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt \
    && find /opt/venv/lib/python*/site-packages -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true \
    && find /opt/venv/lib/python*/site-packages -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true \
    && find /opt/venv/lib/python*/site-packages -name "*.pyc" -delete \
    && find /opt/venv/lib/python*/site-packages -name "*.a" -delete \
    && find /opt/venv/lib/python*/site-packages -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true

COPY dedupe.py /usr/local/bin/dedupe.py
RUN python3 /usr/local/bin/dedupe.py /opt/venv/lib

ENTRYPOINT ["/usr/bin/tini","--"]
