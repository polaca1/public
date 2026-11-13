ARCHS = armv7
TARGET = iphone:9.3:10.0
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = WhatsAppLegacy
WhatsAppLegacy_FILES = $(wildcard Sources/*.m Sources/Protocol/*.m Core/*.c) Vendor/SocketRocket/SRWebSocket.m $(shell python3 -c 'import json; print(" ".join(json.load(open("scripts/crypto-sources.json"))))')
WhatsAppLegacy_CFLAGS = -fobjc-arc -ICore -ISources/Protocol -IVendor/SocketRocket -IVendor/SignalProtocol -IVendor/SignalProtocol/protobuf-c -IVendor/MbedTLS/include -IVendor/MbedTLS/library -IVendor/SignalCurve -IVendor/SignalCurve/ed25519 -IVendor/SignalCurve/ed25519/additions -IVendor/SignalCurve/ed25519/additions/generalized -IVendor/SignalCurve/ed25519/nacl_includes -IVendor/SignalCurve/ed25519/sha512 -DMBEDTLS_CONFIG_FILE=\"wl_crypto_config.h\"
WhatsAppLegacy_FRAMEWORKS = UIKit CoreGraphics CoreImage QuartzCore Foundation Security CFNetwork
WhatsAppLegacy_LIBRARIES = sqlite3 icucore z
WhatsAppLegacy_CODESIGN_FLAGS = -S$(THEOS_PROJECT_DIR)/Resources/entitlements.plist
WhatsAppLegacy_RESOURCE_DIRS = Resources
include $(THEOS_MAKE_PATH)/application.mk
