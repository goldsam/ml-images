#!/bin/bash
set -e

echo "=== Smoke Test for ml-devcontainer ==="
echo ""

# Test Python
echo "Testing Python..."
python3 --version
if ! python3 -c "import sys; assert sys.version_info >= (3, 10)"; then
    echo "ERROR: Python version check failed"
    exit 1
fi
echo "✓ Python OK"
echo ""

# Test PyTorch
echo "Testing PyTorch..."
if ! python3 -c "import torch; print(f'PyTorch version: {torch.__version__}')"; then
    echo "ERROR: PyTorch import failed"
    exit 1
fi
if ! python3 -c "import torchvision; print(f'torchvision version: {torchvision.__version__}')"; then
    echo "ERROR: torchvision import failed"
    exit 1
fi
if ! python3 -c "import torchaudio; print(f'torchaudio version: {torchaudio.__version__}')"; then
    echo "ERROR: torchaudio import failed"
    exit 1
fi
echo "✓ PyTorch OK"
echo ""

# Test Docker CLI
echo "Testing Docker CLI..."
if ! docker --version; then
    echo "ERROR: Docker CLI not found or not working"
    exit 1
fi
echo "✓ Docker CLI OK"
echo ""

# Test docker-compose plugin
echo "Testing docker-compose plugin..."
if ! docker compose version; then
    echo "ERROR: docker-compose plugin not found or not working"
    exit 1
fi
echo "✓ docker-compose plugin OK"
echo ""

# Test .NET SDK
echo "Testing .NET SDK..."
if ! dotnet --version; then
    echo "ERROR: .NET SDK not found or not working"
    exit 1
fi
if ! dotnet --list-sdks; then
    echo "ERROR: .NET SDK list-sdks failed"
    exit 1
fi
echo "✓ .NET SDK OK"
echo ""

echo "=== All smoke tests passed! ==="
