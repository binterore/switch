APP_NAME := BBSwitch
BUNDLE_ID := com.binterore.bbswitch
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
ARCH_BUILD_DIR := $(BUILD_DIR)/arch
ARM64_BINARY := $(ARCH_BUILD_DIR)/$(APP_NAME)-arm64
X86_64_BINARY := $(ARCH_BUILD_DIR)/$(APP_NAME)-x86_64
PACKAGE := $(BUILD_DIR)/$(APP_NAME)-universal.zip
MACOS_MIN_VERSION := 12.0

SWIFT_SOURCES := $(wildcard Sources/*.swift)
SWIFT_FLAGS := -O -framework AppKit -framework Foundation -framework Security

.PHONY: all build package run clean probe

all: build

build: $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)

$(ARM64_BINARY): $(SWIFT_SOURCES)
	@mkdir -p $(ARCH_BUILD_DIR)
	swiftc $(SWIFT_FLAGS) -target arm64-apple-macosx$(MACOS_MIN_VERSION) -o $@ $(SWIFT_SOURCES)

$(X86_64_BINARY): $(SWIFT_SOURCES)
	@mkdir -p $(ARCH_BUILD_DIR)
	swiftc $(SWIFT_FLAGS) -target x86_64-apple-macosx$(MACOS_MIN_VERSION) -o $@ $(SWIFT_SOURCES)

$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME): $(ARM64_BINARY) $(X86_64_BINARY) Resources/Info.plist
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	lipo -create $(ARM64_BINARY) $(X86_64_BINARY) -output $@
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/; fi
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "✔ built $(APP_BUNDLE)"

package: build
	@rm -f $(PACKAGE)
	ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) $(PACKAGE)
	@echo "✔ packaged $(PACKAGE)"

run: build
	open $(APP_BUNDLE)

probe: build
	$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME) --probe

clean:
	rm -rf $(BUILD_DIR)
