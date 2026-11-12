#!/usr/bin/env bash
set -euo pipefail
mkdir -p .tools
cd .tools
curl -fL --retry 3 https://github.com/L1ghtmann/llvm-project/releases/download/test-210562a/iOSToolchain-x86_64.tar.xz -o toolchain.tar.xz
printf '%s\n' 'a72a7a577e2fbe2838b6b5e9c72034fa7d114af96f0e1d4b016f18730ce4056e  toolchain.tar.xz' | sha256sum -c -
mkdir -p toolchain
tar -xJf toolchain.tar.xz -C toolchain --strip-components=2
if [ ! -d sdks/.git ]; then git clone --filter=blob:none --no-checkout https://github.com/theos/sdks.git sdks; fi
git -C sdks sparse-checkout set iPhoneOS9.3.sdk
git -C sdks checkout 0222fd5413cf4b9af096f37b4621afa2688572f7
cp -a sdks/iPhoneOS9.3.sdk patched.sdk
python3 ../scripts/patch-sdk.py patched.sdk
