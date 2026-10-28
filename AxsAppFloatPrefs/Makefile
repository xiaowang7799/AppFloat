include ../AxsAppFloatBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AxsAppFloatPrefs
AxsAppFloatPrefs_FILES = $(wildcard *.m)
AxsAppFloatPrefs_CFLAGS = -fobjc-arc -I../Sources
AxsAppFloatPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation MobileCoreServices
AxsAppFloatPrefs_PRIVATE_FRAMEWORKS = Preferences
AxsAppFloatPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
