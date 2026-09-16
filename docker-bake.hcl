#
# Parameters & variables
#

variable "REGISTRY"     { default = "ghcr.io/" }
variable "IMAGE_PREFIX" { default = "goldsam/ml" }
variable "VERSION"      { default = "latest" }
variable "PLATFORMS"    { default = "linux/amd64" }

# PyTorch build to install in ml-libs. This is the single source of CUDA in the
# whole image graph. Set to "cpu" for a lean CPU-only variant.
variable "TORCH_CUDA"     { default = "cu126" }
variable "TORCH_VERSION"  { default = "" }     # empty = latest for that CUDA build
variable "DOTNET_CHANNEL" { default = "10.0" }

# Git provenance
variable "GIT_REVISION" { default = "" }
variable "GIT_REPO_URL" { default = "" }

# Docker/buildx parameters
variable "CONTEXT_BASE"   { default = "images" }
variable "PYTHON_VERSION" { default = "3.14" }
variable "CACHE_PATH"     { default = ".buildx-cache" }
variable "CACHE_TYPE"     { default = "local" }
variable "CACHE_REGISTRY" { default = "${REGISTRY}" }

# Deployment-branch CUDA base. Supplies CUDA+cuDNN as system libraries for
# ONNX Runtime; unrelated to the pip-wheel CUDA that PyTorch brings.
variable "CUDA_RUNTIME_IMAGE" { default = "nvidia/cuda:12.9.1-cudnn-runtime-ubuntu24.04" }

#
# Functions
#

# Each target gets its own local cache directory. Sharing one directory across
# targets races when buildx builds them in parallel.
function "cache_from" {
  params = [image_name]
  result = [
    CACHE_TYPE == "registry"
      ? "type=registry,ref=${CACHE_REGISTRY}${IMAGE_PREFIX}-${image_name}:build-cache"
      : "type=local,src=${CACHE_PATH}/${image_name}"
  ]
}

function "cache_to" {
  params = [image_name]
  result = [
    CACHE_TYPE == "registry"
      ? "type=registry,ref=${CACHE_REGISTRY}${IMAGE_PREFIX}-${image_name}:build-cache,mode=max"
      : "type=local,dest=${CACHE_PATH}/${image_name},mode=max"
  ]
}

function "image_tags" {
  params = [image_name]
  result = [
    "${REGISTRY}${IMAGE_PREFIX}-${image_name}:${VERSION}"
  ]
}

#
# Build targets
#

# Primary deliverable.
group "default" { targets = ["devcontainer"] }

# Deployment branch: ASP.NET Core on CUDA for ONNX Runtime inference.
group "runtime" { targets = ["dotnet-runtime"] }

# Everything publishable. Used by CI.
group "all" {
  targets = ["cuda-base", "libs", "devcontainer", "dotnet-sdk", "docker-tools", "dotnet-runtime"]
}

target "cuda-base" {
  # split() so PLATFORMS="linux/amd64,linux/arm64" yields two platforms rather
  # than one malformed string.
  platforms  = split(",", PLATFORMS)
  context    = "${CONTEXT_BASE}/cuda-base"
  dockerfile = "Dockerfile"
  pull       = true
  args       = { CUDA_RUNTIME_IMAGE = "${CUDA_RUNTIME_IMAGE}" }
  cache-from = cache_from("cuda-base")
  cache-to   = cache_to("cuda-base")
  tags       = image_tags("cuda-base")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-cuda-base"
    "org.opencontainers.image.description" = "CUDA 12 + cuDNN 9 runtime. The only source of CUDA in this repo."
    "org.opencontainers.image.version"     = "${VERSION}"
    "org.opencontainers.image.source"      = "${GIT_REPO_URL}"
    "org.opencontainers.image.revision"    = "${GIT_REVISION}"
  }
}

target "libs" {
  inherits   = ["cuda-base"]
  context    = "${CONTEXT_BASE}/libs"
  dockerfile = "Dockerfile"
  args = {
    PYTHON_VERSION = "${PYTHON_VERSION}"
    TORCH_CUDA     = "${TORCH_CUDA}"
    TORCH_VERSION  = "${TORCH_VERSION}"
  }
  contexts   = { cuda-base-image = "target:cuda-base" }
  cache-from = cache_from("libs")
  cache-to   = cache_to("libs")
  tags       = image_tags("libs")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-libs"
    "org.opencontainers.image.description" = "PyTorch (${TORCH_CUDA}, --no-deps) + ONNX Runtime on system CUDA, plus the scientific/RL stack"
  }
}

target "dotnet-sdk" {
  inherits   = ["cuda-base"]
  context    = "${CONTEXT_BASE}/dotnet-sdk"
  dockerfile = "Dockerfile"
  args       = { DOTNET_CHANNEL = "${DOTNET_CHANNEL}" }
  contexts   = { cuda-base-image = "target:cuda-base" }
  cache-from = cache_from("dotnet-sdk")
  cache-to   = cache_to("dotnet-sdk")
  tags       = image_tags("dotnet-sdk")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-dotnet-sdk"
    "org.opencontainers.image.description" = ".NET SDK ${DOTNET_CHANNEL} assets image"
  }
}

target "docker-tools" {
  inherits   = ["cuda-base"]
  context    = "${CONTEXT_BASE}/docker-tools"
  dockerfile = "Dockerfile"
  contexts   = { cuda-base-image = "target:cuda-base" }
  cache-from = cache_from("docker-tools")
  cache-to   = cache_to("docker-tools")
  tags       = image_tags("docker-tools")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-docker-tools"
    "org.opencontainers.image.description" = "Docker CLI, buildx and compose plugin assets image"
  }
}

target "devcontainer" {
  inherits   = ["cuda-base"]
  context    = "${CONTEXT_BASE}/devcontainer"
  dockerfile = "Dockerfile"
  contexts = {
    libs-image         = "target:libs"
    docker-tools-image = "target:docker-tools"
    dotnet-sdk-image   = "target:dotnet-sdk"
  }
  cache-from = cache_from("devcontainer")
  cache-to   = cache_to("devcontainer")
  tags       = image_tags("devcontainer")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-devcontainer"
    "org.opencontainers.image.description" = "ML and development devcontainer"
  }
}

target "dotnet-runtime" {
  inherits   = ["cuda-base"]
  context    = "${CONTEXT_BASE}/dotnet-runtime"
  dockerfile = "Dockerfile"
  args       = { DOTNET_CHANNEL = "${DOTNET_CHANNEL}" }
  contexts   = { cuda-base-image = "target:cuda-base" }
  cache-from = cache_from("dotnet-runtime")
  cache-to   = cache_to("dotnet-runtime")
  tags       = image_tags("dotnet-runtime")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-dotnet-runtime"
    "org.opencontainers.image.description" = "ASP.NET Core ${DOTNET_CHANNEL} runtime on CUDA, for ONNX Runtime inference"
  }
}

# Temporarily disabled. The image definition lives in images/azure-ml/.
# Re-enable by uncommenting this target and adding "azure-ml" to group "all".
#
# target "azure-ml" {
#   inherits   = ["cuda-base"]
#   context    = "${CONTEXT_BASE}/azure-ml"
#   dockerfile = "Dockerfile"
#   contexts   = { libs-image = "target:libs" }
#   cache-from = cache_from("azure-ml")
#   cache-to   = cache_to("azure-ml")
#   tags       = image_tags("azure-ml")
#   labels = {
#     "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-azure-ml"
#     "org.opencontainers.image.description" = "Azure ML training image"
#   }
# }
