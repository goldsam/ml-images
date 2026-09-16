# Deployment-branch root: CUDA + cuDNN *runtime* libraries from NVIDIA's own
# image (no compilers, no toolkit).
#
# This branch deliberately does NOT descend from `base`. The devcontainer branch
# gets its CUDA from PyTorch's bundled nvidia-* pip wheels; this branch gets it
# from system packages for ONNX Runtime's native provider. ONNX Runtime 1.30
# targets CUDA 13 (nvidia-cuda-runtime~=13.0, nvidia-cudnn-cu13~=9.0), hence
# the CUDA 13.3 base here. Keeping them separate
# means no single image ever contains two CUDA stacks -- which is exactly the
# bug that made the old images ~6GB of duplicated runtime.
ARG CUDA_RUNTIME_IMAGE=nvidia/cuda:13.3.1-cudnn-runtime-ubuntu26.04
FROM ${CUDA_RUNTIME_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=rt-apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=rt-apt-lists \
    set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        tini \
        tzdata

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

ENTRYPOINT ["/usr/bin/tini","--"]
