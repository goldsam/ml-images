# Core ML stack. This is the ONLY image that installs PyTorch/CUDA.
# Everything downstream inherits it and is pinned by /opt/torch-constraints.txt,
# so no later `pip install` can drag in a second copy of the CUDA runtime.
FROM base-image

# cu132 | cu130 | cpu ... anything under https://download.pytorch.org/whl/
# NOTE: cu134 exists but ships no cp313/cp314 wheels, so it is not usable here.
ARG TORCH_CUDA=cu132
ARG TORCH_VERSION=

WORKDIR /workspace

# Layer 1: PyTorch + its bundled CUDA runtime (~5.5GB, changes rarely).
# Driven by ARGs plus dedupe.py, so it is NOT invalidated by requirements.txt edits.
COPY dedupe.py /usr/local/bin/dedupe.py
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-torch \
    set -ex \
    && pip install --disable-pip-version-check --no-compile --prefer-binary \
        "torch${TORCH_VERSION:+==${TORCH_VERSION}}" \
        --index-url "https://download.pytorch.org/whl/${TORCH_CUDA}" \
    && find /usr/local/lib/python*/site-packages -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true \
    # Static archives are link-time only; nothing loads them at runtime.
    && find /usr/local/lib/python*/site-packages -name "*.a" -delete \
    && python3 /usr/local/bin/dedupe.py

# Layer 2: freeze the CUDA stack into a constraints file and make pip honour it
# globally. Downstream images (and users inside the devcontainer) can install
# whatever they like without silently pulling a second torch/nvidia-* set.
RUN set -ex \
    && { echo "--extra-index-url https://download.pytorch.org/whl/${TORCH_CUDA}"; \
         pip freeze --disable-pip-version-check \
           | grep -iE '^(torch|triton|nvidia[-_]|cuda[-_])' || true ; \
       } > /opt/torch-constraints.txt \
    && cat /opt/torch-constraints.txt
ENV PIP_CONSTRAINT=/opt/torch-constraints.txt

# Layer 3: the rest of the stack. torch is already satisfied, so stable-baselines3
# reuses it instead of resolving its own. Cheap to rebuild when requirements change.
COPY requirements.txt /tmp/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked,id=pip-wheels \
    set -ex \
    && pip install --disable-pip-version-check --no-compile --prefer-binary \
        -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt \
    && find /usr/local/lib/python*/site-packages -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -name "*.pyc" -delete \
    && find /usr/local/lib/python*/site-packages -name "*.pyo" -delete \
    && find /usr/local/lib/python*/site-packages -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true \
    && find /usr/local/lib/python*/site-packages -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true

ENTRYPOINT ["/usr/bin/tini","--"]
