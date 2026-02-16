# Docker Image Architecture Analysis

## Executive Summary

This document analyzes the Docker image build system defined in the `docker/` directory, orchestrated by [docker-bake.hcl](docker-bake.hcl). The system builds a hierarchy of container images for ML development, training, and deployment workloads.

---

## Image Inventory

### 1. **common** ([docker/images/common/Dockerfile](images/common/Dockerfile))
- **Base**: `python:3.13-slim`
- **Purpose**: Minimal foundation with Python 3.11 runtime, system utilities, and `tini` init
- **Packages**: `ca-certificates`, `curl`, `tzdata`, `tini`, `gnupg`, `git`, `build-essential`
- **Dependents**: All other images

### 2. **ml-libs** ([docker/images/ml-libs/Dockerfile](images/ml-libs/Dockerfile))
- **Base**: `common`
- **Purpose**: Core ML/scientific Python libraries (CPU-only)
- **Dependencies**: `requirements.txt` (NumPy, pandas, scikit-learn, Gymnasium, Stable-Baselines3, etc.)
- **Dependents**: `azure-ml`, `gpu-ml`

### 3. **gpu-ml** ([docker/images/gpu-ml/Dockerfile](images/gpu-ml/Dockerfile))
- **Base**: `ml-libs`
- **Purpose**: GPU-enabled ML stack with PyTorch + CUDA
- **Key Feature**: `TORCH_CUDA` build arg for CUDA version selection
- **Dependents**: `devcontainer`

### 4. **azure-ml** ([docker/images/azure-ml/Dockerfile](images/azure-ml/Dockerfile))
- **Base**: `ml-libs`
- **Purpose**: Azure ML-specific training image with Azure SDK packages
- **Key Feature**: Designed for Azure ML compute targets
- **Dependents**: None (leaf node)

### 5. **dotnet-sdk** ([docker/images/dotnet-sdk/Dockerfile](images/dotnet-sdk/Dockerfile))
- **Base**: `common`
- **Purpose**: .NET 8.0 SDK assets image
- **Usage**: Multi-stage copy source for devcontainer
- **Dependents**: `devcontainer`

### 6. **docker-tools** ([docker/images/docker-tools/Dockerfile](images/docker-tools/Dockerfile))
- **Base**: `common`
- **Purpose**: Docker CLI and Buildx plugin assets
- **Usage**: Multi-stage copy source for devcontainer
- **Dependents**: `devcontainer`

### 7. **devcontainer** ([docker/images/devcontainer/Dockerfile](images/devcontainer/Dockerfile))
- **Base**: `gpu-ml`
- **Purpose**: Full development environment with GPU ML, .NET, Docker tools, JupyterLab
- **Multi-stage sources**: `docker-tools`, `dotnet-sdk`
- **Features**: `vscode` user, sudo access, GitHub CLI, dev tools
- **Dependents**: None (leaf node, default build target)

### 8. **train** ([docker/images/train/Dockerfile](images/train/Dockerfile))
- **Base**: `common` (with explicit registry/version args)
- **Purpose**: Production training image with application code
- **Note**: Not in default bake group; used for deployment workflows

---

## Image Dependency Graph

```
                    python:3.13-slim
                          │
                       common
              ┌───────────┼───────────┐
              │           │           │
          ml-libs    dotnet-sdk  docker-tools
          ┌──┴──┐                     │
          │     │                     │
      azure-ml gpu-ml ────────────────┤
                │                     │
                └────── devcontainer ─┘
                    (multi-stage from all)
```

---

## Build System Analysis

### Architecture Decisions

| Aspect | Implementation | Assessment |
|--------|---------------|------------|
| **Build tool** | Docker Buildx Bake | ✅ Modern, supports parallel builds |
| **Caching** | Local or registry-based | ✅ Flexible, CI-optimized |
| **Layer sharing** | Hierarchical base images | ✅ Good deduplication |
| **Content hashing** | Git tree hash per image | ✅ Clever CI optimization |
| **Multi-platform** | Single platform default | ⚠️ Limited to `linux/amd64` |

### Strengths

1. **DRY Configuration**: The `common` target and HCL functions (`cache_from`, `cache_to`, `image_tags`) reduce repetition.

2. **Smart CI Caching**: The [CI_DOCKER_HASHING.md](CI_DOCKER_HASHING.md) approach uses git tree hashes to skip unchanged image builds—an elegant solution for monorepo CI.

3. **Multi-stage Assets Pattern**: Using `dotnet-sdk` and `docker-tools` as copy-only sources avoids bloating the final image with build tooling.

4. **Build Context Isolation**: Each image has its own context directory, preventing accidental cache invalidation from unrelated changes.

---

## Critique

### 1. **Excessive Image Proliferation**

**Problem**: 8 distinct images creates maintenance burden and complex dependency tracking.

**Industry Comparison**: Most projects use 2-3 images:
- A single dev image (with optional GPU layer)
- A slim production image
- Possibly a CI builder image

**Recommendation**: Consider consolidating:
```
base → dev (with optional GPU extras)
base → train (minimal production)
```

### 2. **Redundant GPU Image Split**

**Problem**: Both `azure-ml` and `gpu-ml` extend `ml-libs` with nearly identical PyTorch+CUDA setups. The only difference is Azure SDK packages.

**Better Approach**: Use a single GPU image with optional Azure packages:
```dockerfile
ARG INCLUDE_AZURE=false
RUN if [ "$INCLUDE_AZURE" = "true" ]; then pip install azure-ml-packages; fi
```

### 3. **Overly Clever Hashing System**

**Problem**: ~~The git-tree-hash caching ([image-hash.sh](scripts/image-hash.sh)) is creative but:~~
- ~~Requires committed files (can't test local changes)~~
- ~~Adds CI complexity with custom scripts~~
- ~~Duplicates what registry-based BuildKit caching does natively~~

**Status**: ✅ **RESOLVED** - Custom hash scripts have been removed. The system now uses standard BuildKit registry caching with `type=registry`:
```hcl
cache-to = ["type=registry,ref=...,mode=max"]
cache-from = ["type=registry,ref=..."]
```

This handles content-based caching automatically without custom scripts.

### 4. **Missing Build Targets**

**Problem**: ~~The `train` image exists but isn't in the bake file, creating a disconnect between documented and actual build targets.~~

**Status**: ✅ **RESOLVED** - The `train` target has been added to docker-bake.hcl with proper dependency management.

### 5. **Hardcoded CUDA Version Assumptions**

**Problem**: `TORCH_CUDA=cu121` default may become stale. PyTorch frequently updates CUDA support.

**Better Approach**: Use a matrix build or detect from environment:
```hcl
variable "TORCH_CUDA" { 
  default = env("CUDA_VERSION") != "" ? "cu${env("CUDA_VERSION")}" : "cu121"
}
```

### 6. **No Health Checks**

**Problem**: None of the Dockerfiles define `HEALTHCHECK` instructions, making orchestration harder.

### 7. **Inconsistent User Configuration**

**Problem**: 
- `devcontainer` creates `vscode` user with UID/GID 1000
- `train` uses `app` user
- Other images run as root

This inconsistency can cause permission issues when mounting volumes.

---

## Simplification Recommendations

### Option A: Minimal Restructure

Reduce to 4 images:

```
common (unchanged)
└── ml-libs (merge gpu-ml with ml-libs, CUDA optional via build arg)
    ├── train (production, copies app code)
    └── dev (adds dev tools, .NET, Docker CLI)
```

### Option B: Aggressive Simplification

Reduce to 2 images using build args:

```dockerfile
# Single Dockerfile with feature flags
ARG ENABLE_GPU=false
ARG ENABLE_DEV_TOOLS=false
ARG ENABLE_DOTNET=false

# Conditional installs based on args
RUN if [ "$ENABLE_GPU" = "true" ]; then pip install torch; fi
```

### Recommended Changes

1. **Remove `azure-ml`**: Merge into `gpu-ml` with optional Azure packages
2. **Remove `docker-tools` and `dotnet-sdk`**: Install directly in devcontainer (adds ~100MB but removes 2 image builds)
3. **Standardize user**: Use non-root user in all images with consistent UID
4. ~~**Add the `train` target to bake file**: Ensure parity between docs and config~~ ✅ **COMPLETED**
5. ~~**Replace custom hash scripts**: Trust BuildKit's native caching~~ ✅ **COMPLETED**
6. **Add HEALTHCHECK**: At least for service-oriented images

---

## Comparison with Industry Practices

| Practice | This Project | Industry Standard | Status |
|----------|--------------|-------------------|---------|
| Image count | 8 | 2-4 | 🟡 Still high |
| Custom cache logic | ~~Yes (git hash)~~ | No (BuildKit native) | ✅ Fixed |
| Multi-stage builds | Partial | Full | 🟡 Partial |
| Non-root users | Inconsistent | Consistent | 🟡 Needs work |
| Health checks | None | Standard | 🔴 Missing |
| Automated testing | Not visible | Image scanning, tests | 🔴 Missing |

---

## Conclusion

The Docker setup demonstrates sophisticated use of Buildx Bake and creative CI optimization. However, it exhibits over-engineering symptoms common in projects that evolved organically. The custom hashing system, while clever, duplicates native BuildKit capabilities. The 8-image hierarchy creates maintenance burden without proportional benefits.

**Priority Actions**:
1. Consolidate to 4-5 images maximum
2. ~~Remove custom hash scripts in favor of BuildKit caching~~ ✅ **COMPLETED**
3. Standardize user/permission model
4. ~~Add `train` target to bake file~~ ✅ **COMPLETED**

**Recent Improvements**:
- ✅ Removed custom git hash scripts (`image-hash.sh`, `check-image-exists.sh`)
- ✅ Simplified to standard BuildKit registry/local caching
- ✅ Added missing `train` target to docker-bake.hcl
- ✅ Updated documentation to reflect simplified caching approach

The current system works but carries unnecessary complexity that will compound as the project grows.