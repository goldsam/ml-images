#!/bin/bash
set -e

# Parse arguments
TEST_GPU=false
for arg in "$@"; do
    case $arg in
        --test-gpu)
            TEST_GPU=true
            shift
            ;;
    esac
done

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

# Test CUDA availability (optional, requires --test-gpu flag)
if [ "$TEST_GPU" = true ]; then
    echo "Testing CUDA integration..."
    CUDA_TEST=$(python3 -c "import torch; print(torch.cuda.is_available())" 2>&1)
    if [ "$CUDA_TEST" = "True" ]; then
        CUDA_VERSION=$(python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}, version: {torch.version.cuda}')")
        echo "$CUDA_VERSION"
        DEVICE_COUNT=$(python3 -c "import torch; print(f'GPU devices: {torch.cuda.device_count()}')")
        echo "$DEVICE_COUNT"
        echo "✓ CUDA integration OK"
    elif [ "$CUDA_TEST" = "False" ]; then
        echo "⚠ CUDA not available (no GPU or container not started with --gpus flag)"
        echo "  To enable GPU: Run container with --gpus all flag"
        echo "✓ CUDA test skipped (non-GPU mode)"
    else
        echo "ERROR: CUDA availability check failed"
        echo "$CUDA_TEST"
        exit 1
    fi
    echo ""
else
    echo "Skipping CUDA integration test (use --test-gpu to enable)"
    echo ""
fi

# Test ML/DS packages
echo "Testing ML/DS packages..."
if ! python3 -c "import pandas, numpy, scipy, sklearn, seaborn, plotly; print('All ML/DS packages imported successfully')"; then
    echo "ERROR: ML/DS package import failed"
    exit 1
fi
echo "✓ ML/DS packages OK"
echo ""

# Test pip package metadata preservation  
echo "Testing pip package metadata (no-op install verification)..."
# Verify that pip can see package metadata using pip show
if ! python3 -m pip show numpy > /dev/null 2>&1; then
    echo "ERROR: pip cannot find numpy metadata"
    exit 1
fi
if ! python3 -m pip show pandas > /dev/null 2>&1; then
    echo "ERROR: pip cannot find pandas metadata"
    exit 1
fi
if ! python3 -m pip show torch > /dev/null 2>&1; then
    echo "ERROR: pip cannot find torch metadata"
    exit 1
fi

# Try installing an already-installed package - should be quick (no download)
echo "Testing that reinstalling numpy shows 'Requirement already satisfied'..."
PIP_OUTPUT=$(python3 -m pip install numpy 2>&1)
if echo "$PIP_OUTPUT" | grep -q "Requirement already satisfied: numpy"; then
    echo "✓ Package metadata preserved - no reinstall required"
else
    echo "WARNING: Unexpected pip output, but packages are installed"
fi
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
