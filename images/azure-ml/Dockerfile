# Azure ML training image. PyTorch/CUDA inherited from ml-libs -- this image
# deliberately does NOT install its own torch (that used to duplicate the
# entire CUDA runtime on top of the copy already in the base layer).
FROM libs-image

WORKDIR /workspace

COPY requirements.txt /tmp/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-wheels-azure \
    set -ex \
    && pip install --disable-pip-version-check --no-compile --prefer-binary \
        -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt \
    && find /opt/venv/lib/python*/site-packages -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true \
    && find /opt/venv/lib/python*/site-packages -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true \
    && find /opt/venv/lib/python*/site-packages -name "*.pyc" -delete \
    && find /opt/venv/lib/python*/site-packages -name "*.pyo" -delete \
    && find /opt/venv/lib/python*/site-packages -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true \
    && find /opt/venv/lib/python*/site-packages -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true \
    && find /opt/venv/lib/python*/site-packages -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true

ENTRYPOINT ["/usr/bin/tini","--"]
