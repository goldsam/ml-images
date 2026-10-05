# Dependency contexts, supplied by docker-bake.hcl:
FROM docker-tools-image AS docker-tools
FROM dotnet-sdk-image  AS dotnet-sdk

#
# AWS CLI v2. The official installer unpacks to ~274MB, of which 64MB is debug
# symbols in the bundled interpreter and its extension modules:
#
#   42MB  libpython3.14.so.1.0   -> 6MB stripped
#   39MB  python3.14/lib-dynload -> 18MB stripped
#   12MB  _awscrt.abi3.so        -> 6MB stripped
#
# Stripping those is the one size win with no functional surface: nothing in the
# CLI reads a symbol table, so no command can fail because it is gone. The rest
# of the installer stays as AWS ships it -- every service model, all `help`
# examples, shell completion. Pruning service models would take this to 49MB,
# but it breaks `aws <other-service>` and, less obviously, any SSO-based
# credential profile, months later and with a confusing error. Not worth 1.5% of
# a 7GB image.
#
# Done in a throwaway stage so the zip and the pre-strip tree never reach a
# final layer.
#
# AWS publishes awscli-exe-linux-x86_64-<version>.zip.sig (PGP) alongside the
# download; pinning the sha256 of the bytes that were actually tested is
# stricter, so bump the two together.
#
FROM libs-image AS aws-cli-build
ARG AWSCLI_VERSION=2.37.7
ARG AWSCLI_SHA256=7fccf7854f9f02ad81d6fc28e01098bdf48c72d1aa931eeb36784b8893e0ae14
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists \
    --mount=type=cache,target=/tmp/downloads,sharing=locked,id=awscli-downloads \
    set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends unzip binutils \
    && CACHED="/tmp/downloads/awscli-${AWSCLI_VERSION}.zip" \
    && if [ ! -f "$CACHED" ]; then \
         curl -fsSL -o "$CACHED" \
           "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip"; \
       fi \
    && echo "${AWSCLI_SHA256}  ${CACHED}" | sha256sum -c - \
    && unzip -q "$CACHED" -d /tmp/awscli \
    && mv /tmp/awscli/aws/dist /opt/aws-cli \
    # Not the `aws` launcher itself: it is a PyInstaller bootloader with the
    # application archive appended, which strip would corrupt.
    && find /opt/aws-cli \( -name '*.so' -o -name '*.so.*' \) -print \
        | xargs -r strip --strip-unneeded \
    && rm -rf /tmp/awscli \
    && du -sh /opt/aws-cli

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
# PostgreSQL client comes from PGDG rather than Ubuntu's archive: noble pins
# postgresql-client-16, and psql/pg_dump refuse to dump from a server newer than
# themselves. Pinning the major here instead means the client can be moved
# forward independently of the base distro. `psql` itself is the
# postgresql-client-common wrapper, so /usr/bin/psql resolves whatever major is
# installed.
#
ARG POSTGRES_CLIENT_MAJOR=18
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=devcontainer-apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=devcontainer-apt-lists \
    set -ex \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/keyrings/postgresql-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/postgresql-archive-keyring.gpg \
    # . /etc/os-release, not `lsb_release -cs`: lsb-release is installed by the
    # very apt-get below, so it does not exist yet at this point in the layer.
    && . /etc/os-release \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/postgresql-archive-keyring.gpg] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        gh \
        "postgresql-client-${POSTGRES_CLIENT_MAJOR}" \
        "$(apt-cache search --names-only '^libicu[0-9]+$' | sort -Vr | head -1 | cut -d' ' -f1)" \
        git \
        # `aws help` and `aws <cmd> --help` render through a man formatter; with
        # no groff on PATH every help page dies on "Could not find executable
        # named groff or mandoc". Nothing else in the image graph pulls one in.
        groff-base \
        make \
        openssh-client \
        less \
        iproute2 \
        procps \
        lsb-release \
        vim \
        nano \
        jq \
    && psql --version

#
# Garage CLI -- S3-compatible object storage admin, replacing MinIO's `mc`.
# Used to create buckets and S3 keys against a Garage server (e.g. the MLflow
# artifact store), via `garage bucket create` / `garage key create`.
#
# A single static musl binary, so it needs no runtime dependencies. Garage
# publishes no checksum alongside the download, so the digest below is pinned
# from the bytes that were actually tested -- bump both together.
#
ARG GARAGE_VERSION=v2.4.1
ARG GARAGE_SHA256=ae49f8de4aaee6b5ca305f7cbdccc8cd8a29b2804aac074649f18bfb83d0a2b6
RUN --mount=type=cache,target=/tmp/downloads,sharing=locked,id=garage-downloads \
    set -ex \
    && CACHED="/tmp/downloads/garage-${GARAGE_VERSION}" \
    && if [ ! -f "$CACHED" ]; then \
         curl -fsSL -o "$CACHED" \
           "https://garagehq.deuxfleurs.fr/_releases/${GARAGE_VERSION}/x86_64-unknown-linux-musl/garage"; \
       fi \
    && echo "${GARAGE_SHA256}  ${CACHED}" | sha256sum -c - \
    && install -m 0755 "$CACHED" /usr/local/bin/garage \
    && garage --version

#
# AWS CLI v2 (see the aws-cli-build stage). Covers the object operations
# Garage's own CLI does not -- `aws s3 cp`/`ls`/`sync` against the S3 API, where
# `garage bucket`/`garage key` only administer the server:
#   aws --endpoint-url http://garage:3900 s3 ls
#
COPY --from=aws-cli-build /opt/aws-cli /opt/aws-cli
RUN set -ex \
    && ln -s /opt/aws-cli/aws /usr/local/bin/aws \
    && aws --version

#
# Session Manager plugin -- what `aws ssm start-session` execs to open a shell
# or port-forward through SSM, without which it fails with "SessionManagerPlugin
# is not found". AWS ships it as a .deb whose postinst only symlinks the binary
# into /usr/local/bin; the bundled systemd unit is inert in a container. AWS
# publishes no checksum, so the digest is pinned from the bytes that were
# actually tested -- bump both together.
#
ARG SSM_PLUGIN_VERSION=1.2.835.0
ARG SSM_PLUGIN_SHA256=7c6dcad12518571cc7959a713e6a8ae1bdf6ed66fd9bee37dc189e39ca58ae03
RUN --mount=type=cache,target=/tmp/downloads,sharing=locked,id=ssm-plugin-downloads \
    set -ex \
    && CACHED="/tmp/downloads/session-manager-plugin-${SSM_PLUGIN_VERSION}.deb" \
    && if [ ! -f "$CACHED" ]; then \
         curl -fsSL -o "$CACHED" \
           "https://s3.amazonaws.com/session-manager-downloads/plugin/${SSM_PLUGIN_VERSION}/ubuntu_64bit/session-manager-plugin.deb"; \
       fi \
    && echo "${SSM_PLUGIN_SHA256}  ${CACHED}" | sha256sum -c - \
    && dpkg -i "$CACHED" \
    && session-manager-plugin --version

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
