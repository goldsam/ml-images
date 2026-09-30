#!/usr/bin/env bash
# Print the image tag for the current git ref, using the same rules as CI
# (.github/workflows/build-images.yml). Keep the two in sync.
#
#   main              -> latest
#   release/cuda-12   -> cuda-12
#   cuda-12.1 (tag)   -> cuda-12.1
#   anything else     -> slashes replaced with dashes
set -euo pipefail
ref="${1:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"
case "$ref" in
    main)       echo "latest" ;;
    release/*)  echo "${ref#release/}" ;;
    cuda-*)     echo "$ref" ;;
    *)          echo "$ref" | tr '/' '-' ;;
esac
