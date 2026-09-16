# Common foundation: Python runtime, CA certs, tini init.
# Every other image in this repo descends from this one.
FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1

WORKDIR /workspace

USER root

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked,id=apt-lists \
    apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        tzdata \
        tini \
        gnupg

ENTRYPOINT ["/usr/bin/tini","--"]
