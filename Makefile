DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

# Share the SDK and deployment targets with the PreferenceBundle.
include AxsAppFloatBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AxsAppFloat
AxsAppFloat_FILES = $(wildcard Hooks/*.xm Sources/*.m)
AxsAppFloat_CFLAGS = -fobjc-arc -I./Headers -I./Sources
AxsAppFloat_FRAMEWORKS = UIKit Foundation CoreFoundation
AxsAppFloat_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += AxsAppFloatPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
