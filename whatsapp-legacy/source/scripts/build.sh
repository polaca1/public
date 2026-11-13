#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${WL_TOOLCHAIN:?Set WL_TOOLCHAIN to iOSToolchain bin parent}"
: "${WL_SDK:?Set WL_SDK to the patched iPhoneOS9.3 SDK}"
mkdir -p build/root/Applications/WhatsAppLegacy.app build/root/DEBIAN packages
app=build/root/Applications/WhatsAppLegacy.app
python3 scripts/compile-ios.py
"$WL_TOOLCHAIN/bin/ldid" -SResources/entitlements.plist "$app/WhatsAppLegacy"
cp Resources/Info.plist "$app/Info.plist"
cp Resources/tokens.json "$app/tokens.json"
mkdir -p "$app/Licenses"
cp Vendor/SocketRocket/LICENSE "$app/Licenses/SocketRocket.txt"
cp docs/PIWAPP-LICENSE "$app/Licenses/piwapp.txt"
cp Vendor/SignalProtocol/LICENSE "$app/Licenses/SignalProtocol-GPLv3.txt"
cp Vendor/MbedTLS/LICENSE "$app/Licenses/MbedTLS.txt"
cp control build/root/DEBIAN/control
cat > build/root/DEBIAN/postinst <<'POST'
#!/bin/sh
if command -v uicache >/dev/null 2>&1; then uicache || true; fi
exit 0
POST
chmod 755 build/root/DEBIAN/postinst "$app/WhatsAppLegacy"
find build/root -type d -exec chmod 755 {} +
dpkg-deb --root-owner-group -Zgzip --build build/root packages/whatsapplegacy_0.2.0_iphoneos-arm.deb
python3 scripts/verify.py packages/whatsapplegacy_0.2.0_iphoneos-arm.deb
