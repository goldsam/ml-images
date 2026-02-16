#
# CUDA base stage - triggers early pull to run in parallel with dotnet-builder
#
FROM nvidia/cuda:11.8.0-base-ubuntu22.04 AS python-cude-base

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        ca-certificates \
        libicu70 \
    && rm -rf /var/lib/apt/lists/*

# Install PyTorch with CUDA support - this is the largest layer, so we do it early to allow caching and parallel builds.
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-cache \
    python3 -m pip --no-cache-dir install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu118 \
    && find /usr/local/lib/python*/site-packages -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -name "*.pyc" -delete \
    && find /usr/local/lib/python*/site-packages -name "*.pyo" -delete \
    && find /usr/local/lib/python*/site-packages -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true

# Install ML/DS packages
COPY requirements.txt /tmp/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-cache \
    python3 -m pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt \
    # Smart cleanup: remove artifacts but preserve package metadata for pip
    && find /usr/local/lib/python*/site-packages -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -name "*.pyc" -delete \
    && find /usr/local/lib/python*/site-packages -name "*.pyo" -delete \
    && find /usr/local/lib/python*/site-packages -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true
    # NOTE: .dist-info and .egg-info are preserved so pip can track installed packages
    # This allows project-scoped packages to be installed without reinstalling base packages

#
# Docker tools download stage
#
FROM ubuntu:22.04 AS docker-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        gnupg \
        lsb-release \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

#
# .NET SDK download stage
#
FROM ubuntu:22.04 AS dotnet-builder

ARG DOTNET_VERSION=9.0.102

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/tmp/downloads,sharing=locked,id=dotnet-downloads \
    set -ex \
    && DOTNET_URL="https://dotnetcli.azureedge.net/dotnet/Sdk/${DOTNET_VERSION}/dotnet-sdk-${DOTNET_VERSION}-linux-x64.tar.gz" \
    && DOTNET_CACHE="/tmp/downloads/dotnet-sdk-${DOTNET_VERSION}-linux-x64.tar.gz" \
    && if [ ! -f "${DOTNET_CACHE}" ]; then \
         curl -fSL "${DOTNET_URL}" -o "${DOTNET_CACHE}"; \
       fi \
    && mkdir -p /opt/dotnet \
    && tar -oxzf "${DOTNET_CACHE}" -C /opt/dotnet

#
# Final image
#
FROM python-cude-base

# Copy Docker tools from builder stage
COPY --from=docker-builder /usr/bin/docker /usr/bin/docker
COPY --from=docker-builder /usr/libexec/docker /usr/libexec/docker

# Copy .NET SDK from builder stage
COPY --from=dotnet-builder /opt/dotnet /opt/dotnet

# Set up .NET environment
ENV DOTNET_ROOT=/opt/dotnet
ENV PATH="$DOTNET_ROOT:$PATH"
RUN ln -s "$DOTNET_ROOT/dotnet" /usr/local/bin/dotnet