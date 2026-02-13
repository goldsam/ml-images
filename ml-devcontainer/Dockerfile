#
# CUDA base stage - triggers early pull to run in parallel with dotnet-builder
#
FROM nvidia/cuda:11.8.0-base-ubuntu22.04 AS cuda-base

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        ca-certificates \
        libicu70 \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m pip --no-cache-dir install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu118

#
# Docker tools builder - uses minimal base image
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
FROM cuda-base

# Copy Docker tools from builder stage
COPY --from=docker-builder /usr/bin/docker /usr/bin/docker
COPY --from=docker-builder /usr/libexec/docker /usr/libexec/docker

# Copy .NET SDK from builder stage
COPY --from=dotnet-builder /opt/dotnet /opt/dotnet

# Set up .NET environment
ENV DOTNET_ROOT=/opt/dotnet
ENV PATH="$DOTNET_ROOT:$PATH"
RUN ln -s "$DOTNET_ROOT/dotnet" /usr/local/bin/dotnet