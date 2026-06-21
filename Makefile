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
	@APP="$$(xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe -showBuildSettings 2>/dev/null | \
		awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{d=$$2} / FULL_PRODUCT_NAME =/{p=$$2} END{print d"/"p}')"; \
	echo "Launching $$APP"; \
	open "$$APP"

pre-push: lint test build
	@echo "pre-push checks passed"
