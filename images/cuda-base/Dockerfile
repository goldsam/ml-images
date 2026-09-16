# The single root of every image in this repo, and the only source of CUDA.
#
# CUDA and cuDNN come from NVIDIA's runtime image as system libraries. Both
# PyTorch (installed with --no-deps) and ONNX Runtime bind to these, so no image
# ever carries a second, private CUDA stack in site-packages.
#
# Deliberately NOT the -devel variant: no nvcc, no toolkit, no headers.
ARG CUDA_RUNTIME_IMAGE=nvidia/cuda:13.3.1-cudnn-runtime-ubuntu24.04
FROM ${CUDA_RUNTIME_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists \
    set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        tini \
        tzdata

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini","--"]
