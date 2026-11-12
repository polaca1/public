#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
cc -std=c99 -Wall -Wextra -Werror -fsanitize=address,undefined -ICore Core/wl_frame.c tests/test_frame.c -o build/test-frame
build/test-frame
