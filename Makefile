# Convenience wrapper around Buildx Bake.
#
#   make build                 # default group (devcontainer + its deps)
#   make build all             # every publishable image
#   make build ml-libs         # one target
#   make build TORCH_CUDA=cpu  # lean CPU-only variant
#   make build VERSION=dev     # override any docker-bake.hcl variable
#   make print                 # resolved bake config
#   make clean-cache

# No defaults for REGISTRY/VERSION/TORCH_CUDA/DOTNET_CHANNEL/... on purpose:
# docker-bake.hcl is the single source of truth. Setting them here too means the
# two silently drift apart and `make build` quietly builds something other than
# what the bake file says. Only variables you set on the command line are
# forwarded (see FORWARD below).
CACHE_TYPE ?= local
CACHE_DIR  ?= .buildx-cache

MAKEFILE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
CACHE_PATH   := $(MAKEFILE_DIR)/$(CACHE_DIR)
BUILDX_FLAGS ?= --allow=fs=$(CACHE_PATH) -f $(MAKEFILE_DIR)/docker-bake.hcl

# Everything after the first goal is treated as a list of bake targets.
BAKE_TARGETS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))

GIT_REVISION := $(shell git rev-parse HEAD 2>/dev/null)
GIT_REPO_URL := $(shell git config --get remote.origin.url 2>/dev/null)

# Forward only the variables that were actually set, so unset ones fall through
# to the defaults in docker-bake.hcl.
FORWARD := REGISTRY IMAGE_PREFIX VERSION TORCH_CUDA TORCH_VERSION DOTNET_CHANNEL \
           CUDA_RUNTIME_IMAGE PLATFORMS
buildx_env = CACHE_PATH=$(CACHE_PATH) CACHE_TYPE=$(CACHE_TYPE) \
             GIT_REVISION=$(GIT_REVISION) GIT_REPO_URL=$(GIT_REPO_URL) \
             $(foreach v,$(FORWARD),$(if $($(v)),$(v)=$($(v)),))

.PHONY: help build push print test verify verify-gpu clean-cache
.DEFAULT_GOAL := help

$(CACHE_PATH):
	@mkdir -p $(CACHE_PATH)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables: REGISTRY IMAGE_PREFIX VERSION TORCH_CUDA DOTNET_CHANNEL CACHE_TYPE"

build: $(CACHE_PATH) ## Build image(s); extra args are bake targets
	$(buildx_env) docker buildx bake $(BUILDX_FLAGS) $(BAKE_TARGETS)

push: $(CACHE_PATH) ## Build and push image(s)
	$(buildx_env) docker buildx bake $(BUILDX_FLAGS) --push $(BAKE_TARGETS)

print: ## Print the resolved bake configuration
	@$(buildx_env) docker buildx bake $(BUILDX_FLAGS) --print $(BAKE_TARGETS)

verify: ## Build all images and run the full test pipeline
	./verify.sh

verify-gpu: ## Same, but require the GPU
	./verify.sh --gpu

# Ask bake for the devcontainer's actual tag rather than reconstructing it.
test: ## Run the smoke test against a locally built devcontainer
	./smoke-test.sh --image $$($(buildx_env) docker buildx bake $(BUILDX_FLAGS) --print devcontainer \
	  | python3 -c 'import json,sys; print(json.load(sys.stdin)["target"]["devcontainer"]["tags"][0])')

clean-cache: ## Remove the local buildx cache
	@rm -rf $(CACHE_PATH)

# Swallow extra goals so "make build ml-libs" doesn't error.
%:
	@:
