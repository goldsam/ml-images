# .NET SDK assets image. Not used directly -- devcontainer COPYs /opt/dotnet out of it.
FROM base-image

ARG DOTNET_CHANNEL=9.0

ENV DOTNET_SDK_ROOT=/opt/dotnet
ENV DOTNET_NOLOGO=true
ENV DOTNET_CLI_TELEMETRY_OPTOUT=true

RUN --mount=type=cache,target=/tmp/downloads,sharing=locked,id=dotnet-downloads \
    --mount=type=cache,target=/root/.dotnet,sharing=locked,id=dotnet-cache \
    set -ex \
    && if [ ! -f /tmp/downloads/dotnet-install.sh ]; then \
         curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/downloads/dotnet-install.sh; \
         chmod +x /tmp/downloads/dotnet-install.sh; \
       fi \
    && bash /tmp/downloads/dotnet-install.sh --channel "${DOTNET_CHANNEL}" --install-dir "$DOTNET_SDK_ROOT" --no-path

ENV PATH="$DOTNET_SDK_ROOT:$PATH"
