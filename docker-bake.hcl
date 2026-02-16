#
# Parameters & variables
#

# Project/environment parameters
variable "REGISTRY"     { default = "ghcr.io/" }
variable "IMAGE_PREFIX" { default = "algotrader" }
variable "VERSION"      { default = "latest" }
variable "PLATFORMS"    { default = "linux/amd64" }
variable "TORCH_CUDA"   { default = "cu121" }

# Git revision (commit hash)
variable "GIT_REVISION" { default = "" }
variable "GIT_REPO_URL" { default = ""}

# Docker/buildx parameters
variable "CONTEXT_BASE"   { default = "docker/images" }
variable "CACHE_PATH"     { default = ".buildx-cache" }
variable "CACHE_TYPE"     { default = "local" }
variable "CACHE_REGISTRY" { default = "${REGISTRY}" }

#
# functions
#

function "cache_from" {
  params = [image_name]
  result = [
    CACHE_TYPE == "registry" ? "type=registry,ref=${CACHE_REGISTRY}${IMAGE_PREFIX}-${image_name}:build-cache" : "type=local,src=${CACHE_PATH}"
  ]
}

function "cache_to" {
  params = [image_name]
  result = [
    CACHE_TYPE == "registry" ? "type=registry,ref=${CACHE_REGISTRY}${IMAGE_PREFIX}-${image_name}:build-cache,mode=max" : "type=local,dest=${CACHE_PATH},mode=max"
  ]
}

# Image tagging function
function "image_tags" {
  params = [image_name]
  result = [
    "${REGISTRY}${IMAGE_PREFIX}-${image_name}:${VERSION}"
  ]
}

#
# Build targets
#

group "default" { targets = ["devcontainer"] }

target "base" {
  platforms = ["${PLATFORMS}"]
  context    = "${CONTEXT_BASE}/base"
  dockerfile = "Dockerfile"
  pull       = true
  cache-from = cache_from("base")
  cache-to   = cache_to("base")
  tags       = image_tags("base")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-base"
    "org.opencontainers.image.description" = "Common foundation with OS, Python 3.11, and shared tools"
    "org.opencontainers.image.version"     = "${VERSION}"
    "org.opencontainers.image.source"      = "${GIT_REPO_URL}"
    "org.opencontainers.image.revision"    = "${GIT_REVISION}"
  }
}

target "ml-libs" {
  inherits   = ["base"]
  context    = "${CONTEXT_BASE}/ml-libs"
  dockerfile = "Dockerfile"
  contexts = {
    base-image = "target:base"
  }
  cache-from = cache_from("ml-libs")
  cache-to   = cache_to("ml-libs")
  tags       = image_tags("ml-libs")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-ml-libs"
    "org.opencontainers.image.description" = "Scientific and RL libraries (NumPy, SciPy, Gymnasium, Stable-Baselines3)"
  }
}

target "azure-ml" {
  inherits   = ["base"]
  context    = "${CONTEXT_BASE}/azure-ml"
  dockerfile = "Dockerfile"
  args = {
    TORCH_CUDA = "${TORCH_CUDA}"
  }
  contexts = {
    ml-libs-image = "target:ml-libs"
  }
  cache-from = cache_from("azure-ml")
  cache-to   = cache_to("azure-ml")
  tags       = image_tags("azure-ml")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-azure-ml"
    "org.opencontainers.image.description" = "Azure ML training image with GPU support"
  }
}

target "gpu-ml" {
  inherits   = ["base"]
  context    = "${CONTEXT_BASE}/gpu-ml"
  dockerfile = "Dockerfile"
  args = {
    TORCH_CUDA = "${TORCH_CUDA}"
  }
  contexts = {
    ml-libs-image = "target:ml-libs"
  }
  cache-from = cache_from("gpu-ml")
  cache-to   = cache_to("gpu-ml")
  tags       = image_tags("gpu-ml")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-gpu-ml"
    "org.opencontainers.image.description" = "GPU ML training image with CUDA support"
  }
}

target "dotnet-sdk" {
  inherits   = ["base"]
  context = "${CONTEXT_BASE}/dotnet-sdk"
  dockerfile = "Dockerfile"
  contexts = {
    base-image = "target:base"
  }
  cache-from = cache_from("dotnet-sdk")
  cache-to   = cache_to("dotnet-sdk")
  tags       = image_tags("dotnet-sdk")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-dotnet-sdk"
    "org.opencontainers.image.description" = ".NET SDK assets image"
  }
}

target "docker-tools" {
  inherits   = ["base"]
  context = "${CONTEXT_BASE}/docker-tools"
  dockerfile = "Dockerfile"
  contexts = {
    base-image = "target:base"
  }
  cache-from = cache_from("docker-tools")
  cache-to   = cache_to("docker-tools")
  tags       = image_tags("docker-tools")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-docker-tools"
    "org.opencontainers.image.description" = "Docker tools and utilities assets image"
  }
}

target "devcontainer" {
  inherits   = ["base"]
  context = "${CONTEXT_BASE}/devcontainer"
  dockerfile = "Dockerfile"
  contexts = {
    gpu-ml-image = "target:gpu-ml"
    docker-tools-image = "target:docker-tools"
    dotnet-sdk-image = "target:dotnet-sdk"
  }
  cache-from = cache_from("devcontainer")
  cache-to   = cache_to("devcontainer")
  tags       = image_tags("devcontainer")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-devcontainer"
    "org.opencontainers.image.description" = "ML and development devcontainer"
  }
}

target "train" {
  inherits   = ["base"]
  context = "${CONTEXT_BASE}/train"
  dockerfile = "Dockerfile"
  args = {
    TORCH_CUDA = "${TORCH_CUDA}"
    REGISTRY = "${REGISTRY}"
    IMAGE_PREFIX = "${IMAGE_PREFIX}"
    BASE_VERSION = "${VERSION}"
  }
  contexts = {
    base-image = "target:base"
  }
  cache-from = cache_from("train")
  cache-to   = cache_to("train")
  tags       = image_tags("train")
  labels = {
    "org.opencontainers.image.title"       = "${IMAGE_PREFIX}-train"
    "org.opencontainers.image.description" = "Production training image with application code"
  }
}
