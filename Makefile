# SPDX-License-Identifier: GPL-3.0-only

.PHONY: all build debug-build generate-build-info generate-icons install run test smoke-test smoke-test-check license-check license-fix check-build-deps check-smoke-test-deps clean publish save-codesign-identity clear-codesign-identity

all: build

CODESIGN_IDENTITY_FILE ?= .codesign_identity
BUILD_INFO_SWIFT ?= .build/BuildInfo.generated.swift
LICENSEOPS ?= lops
RSVG_CONVERT ?= rsvg-convert
BUILD_DEPENDENCIES = bash swiftc lipo codesign git shasum awk find date
SMOKE_TEST_DEPENDENCIES = bash open alerter grep awk ps kill tail wc head make
APP_SWIFT_SOURCES = $(sort $(wildcard src/*.swift)) $(BUILD_INFO_SWIFT)
TEST_SWIFT_SOURCES = src/MachineModelPolicy.swift src/NotificationDisplayTarget.swift src/NotificationDisplayTargetPolicy.swift src/NotifyPointLaunchMode.swift src/NotifyPointMenuPolicy.swift src/NotifyPointMenuPreviewIPC.swift src/NotifyPointSettings.swift src/NotificationPosition.swift src/NotificationPositionGridLayout.swift src/NotificationGeometry.swift src/NotificationPolicyTypes.swift src/NotificationMovePolicy.swift src/NotificationCenterStatePolicy.swift src/ScreenResolutionPolicy.swift src/TreeTraversal.swift src/NotificationController.swift src/NotificationWindowPlacementEngine.swift tests/NotificationBehaviorTests.swift tests/NotificationPositionPickerTests.swift

ifneq ("$(wildcard $(CODESIGN_IDENTITY_FILE))","")
CODESIGN_IDENTITY ?= $(shell cat $(CODESIGN_IDENTITY_FILE))
else
CODESIGN_IDENTITY ?= -
endif

define warn_adhoc_signing
	@if [ "$(CODESIGN_IDENTITY)" = "-" ]; then \
		echo "warning: using ad-hoc signing (-)."; \
		echo "warning: macOS Accessibility permissions may need re-approval for each build."; \
		echo "warning: run 'make save-codesign-identity CODESIGN_IDENTITY=\"Apple Development: Your Name (TEAMID)\"' to stabilize signing."; \
	fi
endef

check-build-deps:
	@missing=0; \
	for command in $(BUILD_DEPENDENCIES); do \
		if ! command -v "$$command" >/dev/null 2>&1; then \
			echo "error: missing required build dependency '$$command'"; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then \
		echo "hint: install Xcode Command Line Tools with 'xcode-select --install'."; \
		exit 1; \
	fi

check-smoke-test-deps: check-build-deps
	@missing=0; \
	for command in $(SMOKE_TEST_DEPENDENCIES); do \
		if ! command -v "$$command" >/dev/null 2>&1; then \
			echo "error: missing required smoke-test dependency '$$command'"; \
			if [ "$$command" = "alerter" ]; then \
				echo "hint: install it with 'brew install vjeantet/alerter/alerter'"; \
			fi; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then \
		echo "hint: make sure macOS allows the chosen notification sender to post notifications."; \
		exit 1; \
	fi

build: check-build-deps
	@mkdir -p .build
	@$(MAKE) generate-build-info
	@mkdir -p NotifyPoint.app/Contents/MacOS
	@mkdir -p NotifyPoint.app/Contents/Resources
	@cp src/Info.plist NotifyPoint.app/Contents/
	@cp LICENSE NotifyPoint.app/Contents/Resources/
	@cp src/assets/app-icon/icon.icns NotifyPoint.app/Contents/Resources/
	@cp src/assets/menu-bar-icon/MenuBarIcon*.png NotifyPoint.app/Contents/Resources/
	swiftc $(APP_SWIFT_SOURCES) -o NotifyPoint.app/Contents/MacOS/NotifyPoint-x86_64 -O -target x86_64-apple-macos14.0
	swiftc $(APP_SWIFT_SOURCES) -o NotifyPoint.app/Contents/MacOS/NotifyPoint-arm64 -O -target arm64-apple-macos14.0
	lipo -create -output NotifyPoint.app/Contents/MacOS/NotifyPoint NotifyPoint.app/Contents/MacOS/NotifyPoint-x86_64 NotifyPoint.app/Contents/MacOS/NotifyPoint-arm64
	rm NotifyPoint.app/Contents/MacOS/NotifyPoint-x86_64 NotifyPoint.app/Contents/MacOS/NotifyPoint-arm64
	$(warn_adhoc_signing)
	codesign --entitlements src/NotifyPoint.entitlements -fvs "$(CODESIGN_IDENTITY)" NotifyPoint.app

debug-build: check-build-deps
	@mkdir -p .build
	@$(MAKE) generate-build-info
	@mkdir -p NotifyPoint.app/Contents/MacOS
	@mkdir -p NotifyPoint.app/Contents/Resources
	@cp src/Info.plist NotifyPoint.app/Contents/
	@cp LICENSE NotifyPoint.app/Contents/Resources/
	@cp src/assets/app-icon/icon.icns NotifyPoint.app/Contents/Resources/
	@cp src/assets/menu-bar-icon/MenuBarIcon*.png NotifyPoint.app/Contents/Resources/
	swiftc $(APP_SWIFT_SOURCES) -o NotifyPoint.app/Contents/MacOS/NotifyPoint-x86_64 -Onone -g -D NOTIFYPOINT_DEBUG_BUILD -target x86_64-apple-macos14.0
	swiftc $(APP_SWIFT_SOURCES) -o NotifyPoint.app/Contents/MacOS/NotifyPoint-arm64 -Onone -g -D NOTIFYPOINT_DEBUG_BUILD -target arm64-apple-macos14.0
	lipo -create -output NotifyPoint.app/Contents/MacOS/NotifyPoint NotifyPoint.app/Contents/MacOS/NotifyPoint-x86_64 NotifyPoint.app/Contents/MacOS/NotifyPoint-arm64
	rm NotifyPoint.app/Contents/MacOS/NotifyPoint-x86_64 NotifyPoint.app/Contents/MacOS/NotifyPoint-arm64
	$(warn_adhoc_signing)
	codesign --entitlements src/NotifyPoint.entitlements -fvs "$(CODESIGN_IDENTITY)" NotifyPoint.app

generate-build-info:
	@mkdir -p .build
	@BUILD_COMMIT=$$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown); \
	BUILD_DIRTY=$$(if git diff --quiet --ignore-submodules HEAD -- 2>/dev/null && git diff --cached --quiet --ignore-submodules -- 2>/dev/null && [ -z "$$(git ls-files --others --exclude-standard -- src tests Makefile 2>/dev/null)" ]; then echo clean; else echo dirty; fi); \
	BUILD_TIMESTAMP=$$(date -u +%Y-%m-%dT%H:%M:%SZ); \
	SOURCE_FINGERPRINT=$$((find src -type f -print 2>/dev/null; find tests -type f -print 2>/dev/null; printf '%s\n' Makefile) | LC_ALL=C sort | while IFS= read -r file; do shasum "$$file"; done | shasum | awk '{print $$1}'); \
	printf '%s\n' \
		'struct GeneratedBuildInfo {' \
		"    static let gitCommit = \"$$BUILD_COMMIT\"" \
		"    static let gitDirtyState = \"$$BUILD_DIRTY\"" \
		"    static let buildTimestamp = \"$$BUILD_TIMESTAMP\"" \
		"    static let sourceFingerprint = \"$$SOURCE_FINGERPRINT\"" \
		'}' > "$(BUILD_INFO_SWIFT)"

generate-icons:
	$(RSVG_CONVERT) --width=1024 --height=1024 --output=src/assets/icon.png src/assets/icon.svg
	jbang scripts/icons/GenerateIcons.java

install: build
	@killall NotifyPoint 2>/dev/null || true
	@mkdir -p "$(HOME)/Applications"
	@ditto NotifyPoint.app "$(HOME)/Applications/NotifyPoint.app"
	@open "$(HOME)/Applications/NotifyPoint.app"

run:
	@open NotifyPoint.app

test: check-build-deps
	@mkdir -p .build
	@if [ -f tests/NotificationBehaviorTests.swift ]; then \
		swiftc $(TEST_SWIFT_SOURCES) -o .build/NotificationBehaviorTests; \
		.build/NotificationBehaviorTests; \
	else \
		echo "No NotificationBehaviorTests on this branch."; \
	fi

smoke-test: check-smoke-test-deps
	@./scripts/smoke-test-alerter.sh $(SMOKE_TEST_ARGS)

smoke-test-check:
	@bash -n scripts/smoke-test-alerter.sh

license-check:
	$(LICENSEOPS) check

license-fix:
	$(LICENSEOPS) fix

clean:
	@rm -rf NotifyPoint.app NotifyPoint.app.tar.gz .build

publish:
	@tar --uid=0 --gid=0 -czf NotifyPoint.app.tar.gz NotifyPoint.app
	@shasum -a 256 NotifyPoint.app.tar.gz | cut -d ' ' -f 1
	@echo "don't forget to change the version number"

save-codesign-identity:
	@test -n "$(CODESIGN_IDENTITY)" || (echo "error: set CODESIGN_IDENTITY to your Apple signing identity"; exit 1)
	@test "$(CODESIGN_IDENTITY)" != "-" || (echo "error: refusing to save ad-hoc identity '-'"; exit 1)
	@printf "%s" "$(CODESIGN_IDENTITY)" > "$(CODESIGN_IDENTITY_FILE)"
	@echo "Saved codesign identity to $(CODESIGN_IDENTITY_FILE)"

clear-codesign-identity:
	@rm -f "$(CODESIGN_IDENTITY_FILE)"
	@echo "Cleared $(CODESIGN_IDENTITY_FILE); builds will use ad-hoc signing unless CODESIGN_IDENTITY is set."
