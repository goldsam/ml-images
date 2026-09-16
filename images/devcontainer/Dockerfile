# Dependency contexts, supplied by docker-bake.hcl:
FROM docker-tools-image AS docker-tools
FROM dotnet-sdk-image  AS dotnet-sdk

# Full development environment: the ML/ONNX stack plus .NET, Docker CLI and
# Jupyter. Everything needed to build AND test an ONNX-targeting C# app.
FROM libs-image

USER root

#
# vscode user
#
ARG UID=1000
ARG GID=1000
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists \
    set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends sudo \
    # Ubuntu 24.04 ships a default `ubuntu` user at UID/GID 1000, which Debian
    # did not. Free the id before claiming it for vscode.
    && if existing=$(getent passwd ${UID} | cut -d: -f1) && [ -n "$existing" ]; then \
         userdel -r "$existing" 2>/dev/null || userdel "$existing"; \
       fi \
    && if existing=$(getent group ${GID} | cut -d: -f1) && [ -n "$existing" ]; then \
         groupdel "$existing" 2>/dev/null || true; \
       fi \
    && groupadd -g ${GID} vscode \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash vscode \
    && echo "vscode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

#
# .NET SDK (binaries only, from the assets image)
#
COPY --from=dotnet-sdk /opt/dotnet /opt/dotnet
ENV DOTNET_ROOT=/opt/dotnet \
    DOTNET_NOLOGO=true \
    DOTNET_CLI_TELEMETRY_OPTOUT=true \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
ENV PATH="$DOTNET_ROOT:$PATH"
RUN ln -s "$DOTNET_ROOT/dotnet" /usr/local/bin/dotnet

#
# Docker CLI + buildx + compose plugins (binaries only, from the assets image).
# Taking compose from docker-tools rather than downloading it separately keeps
# the version tied to the Docker apt repo and drops a network dependency.
#
COPY --from=docker-tools /usr/bin/docker /usr/bin/docker
COPY --from=docker-tools /usr/libexec/docker/cli-plugins/ /usr/libexec/docker/cli-plugins/
RUN set -ex \
    && chmod +x /usr/bin/docker /usr/libexec/docker/cli-plugins/* \
    && ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose \
    && groupadd -f docker \
    && usermod -aG docker vscode
ENV DOCKER_BUILDKIT=1

#
# Interactive dev tooling
#
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=devcontainer-apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=devcontainer-apt-lists \
    set -ex \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        gh \
        "$(apt-cache search --names-only '^libicu[0-9]+$' | sort -Vr | head -1 | cut -d' ' -f1)" \
        git \
        make \
        openssh-client \
        less \
        iproute2 \
        procps \
        lsb-release \
        vim \
        nano \
        jq

#
# Development-only Python packages (JupyterLab etc). Last layer: changes here
# rebuild ~200MB, not the 3GB CUDA stack underneath.
#
COPY requirements.txt /tmp/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-wheels-dev \
    set -ex \
    && python3 -m pip install --disable-pip-version-check --no-compile --prefer-binary \
        -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt \
    && find /usr/local/lib/python*/site-packages -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -name "*.pyc" -delete \
    && find /usr/local/lib/python*/site-packages -name "*.pyo" -delete \
    && find /usr/local/lib/python*/site-packages -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true

RUN chown -R vscode:vscode /workspace

USER vscode
WORKDIR /workspace
CMD ["/bin/bash"]
