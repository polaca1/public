ARCHS = armv7
TARGET = iphone:9.3:10.0
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = WhatsAppLegacy
WhatsAppLegacy_FILES = Sources/App.m Core/wl_frame.c Vendor/SocketRocket/SRWebSocket.m
WhatsAppLegacy_CFLAGS = -fobjc-arc -IVendor/SocketRocket
WhatsAppLegacy_FRAMEWORKS = UIKit CoreGraphics Foundation Security CFNetwork
WhatsAppLegacy_LIBRARIES = sqlite3 icucore
WhatsAppLegacy_RESOURCE_DIRS = Resources
include $(THEOS_MAKE_PATH)/application.mk
