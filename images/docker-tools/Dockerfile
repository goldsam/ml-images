# Docker CLI + plugins assets image. Not used directly -- devcontainer COPYs the
# binaries out of it, so none of the apt metadata ends up in the final image.
FROM base-image

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists \
    --mount=type=cache,target=/tmp/downloads,sharing=locked,id=docker-downloads \
    set -ex \
    && apt-get update \
    && install -m 0755 -d /etc/apt/keyrings \
    && if [ ! -f /tmp/downloads/docker.gpg ]; then \
         curl -fsSL https://download.docker.com/linux/debian/gpg -o /tmp/downloads/docker.gpg; \
       fi \
    && gpg --dearmor < /tmp/downloads/docker.gpg > /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) \
        signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
            > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-buildx-plugin \
        docker-compose-plugin
