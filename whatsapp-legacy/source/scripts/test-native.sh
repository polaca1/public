#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/build-crypto.py -shared -lsqlite3 -o build/libwlcrypto.so
python3 tests/test_native_signal.py
