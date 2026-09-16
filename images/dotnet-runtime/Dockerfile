# ASP.NET Core runtime on CUDA, for deploying C# services that run inference
# through ONNX Runtime's GPU provider (Microsoft.ML.OnnxRuntime.Gpu, CUDA 13).
#
# Runtime only -- no SDK. The devcontainer carries the SDK; shipping both here
# would duplicate the shared framework for no benefit.
FROM cuda-runtime-image

ARG DOTNET_CHANNEL=10.0

ENV DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_NOLOGO=true \
    DOTNET_CLI_TELEMETRY_OPTOUT=true \
    ASPNETCORE_HTTP_PORTS=8080

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=rt-apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=rt-apt-lists \
    --mount=type=cache,target=/tmp/downloads,sharing=locked,id=dotnet-downloads \
    set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends curl \
    # .NET needs libicu for globalization; the package is version-suffixed and
    # differs between Ubuntu releases, so resolve it rather than hardcoding.
    && apt-get install -y --no-install-recommends \
        "$(apt-cache search --names-only '^libicu[0-9]+$' | sort -Vr | head -1 | cut -d' ' -f1)" \
    && if [ ! -f /tmp/downloads/dotnet-install.sh ]; then \
         curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/downloads/dotnet-install.sh; \
         chmod +x /tmp/downloads/dotnet-install.sh; \
       fi \
    # --runtime aspnetcore pulls the ASP.NET Core shared framework, which is a
    # superset of the base runtime, so console/worker apps work too.
    && bash /tmp/downloads/dotnet-install.sh \
        --channel "${DOTNET_CHANNEL}" \
        --runtime aspnetcore \
        --install-dir "$DOTNET_ROOT" \
        --no-path \
    && ln -s "$DOTNET_ROOT/dotnet" /usr/local/bin/dotnet \
    && dotnet --list-runtimes

# Non-root by default; apps are expected to COPY their publish output in.
RUN groupadd -r app && useradd -r -g app -m -d /home/app app
WORKDIR /opt/app
USER app

EXPOSE 8080
