# ML DevContainer

A production-ready ML development container with CUDA support, PyTorch, and essential ML/DS tools.

## Features

- **Python 3** with CUDA 11.8 support
- **PyTorch** with CUDA acceleration
- **Machine Learning Libraries** (see requirements.txt)
- **Docker CLI** for container-based workflows
- **.NET SDK 9.0** for cross-platform development

## Usage

### Pull from GitHub Container Registry

```bash
docker pull ghcr.io/<your-username>/ml-devcontainer:latest
```

### Build Locally

```bash
docker build -t ml-devcontainer .
```

### Run with GPU Support

```bash
docker run --rm --gpus all -it ghcr.io/<your-username>/ml-devcontainer:latest
```

## GitHub Actions

This repository includes a GitHub Actions workflow that automatically builds and publishes the Docker image to GitHub Container Registry (ghcr.io) on:
- Push to `main` or `develop` branches
- Version tags (e.g., `v1.0.0`)
- Pull requests (build only, no push)

## Requirements

- Docker with NVIDIA GPU support for local builds
- GitHub account for publishing to ghcr.io

## License

MIT
