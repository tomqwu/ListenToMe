.PHONY: gen build test lint run pre-push

SHELL := /bin/bash
.SHELLFLAGS := -eo pipefail -c

gen:
	xcodegen generate

build: gen
	xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe \
		-destination 'platform=macOS' -configuration Debug build | xcbeautify || \
	xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe \
		-destination 'platform=macOS' -configuration Debug build

test:
	swift test

lint:
	swiftlint lint --quiet

run: build
	open ./build/Debug/ListenToMe.app 2>/dev/null || \
	open $$(xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe -showBuildSettings | \
		awk '/BUILT_PRODUCTS_DIR/{d=$$3}/FULL_PRODUCT_NAME/{p=$$3}END{print d"/"p}')

pre-push: lint test build
	@echo "pre-push checks passed"
