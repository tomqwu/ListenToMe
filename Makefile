.PHONY: gen build test lint run pre-push e2e release

SHELL := /bin/bash
.SHELLFLAGS := -eo pipefail -c

# Optional local signing override (gitignored) — define SIGN_FLAGS for a stable identity
# so granted macOS permissions (TCC) persist across rebuilds. See signing.local.mk.example.
-include signing.local.mk

gen:
	xcodegen generate

build: gen
	@if command -v xcbeautify >/dev/null 2>&1; then \
		xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe \
			-destination 'platform=macOS' -configuration Debug build $(SIGN_FLAGS) | xcbeautify; \
	else \
		xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe \
			-destination 'platform=macOS' -configuration Debug build $(SIGN_FLAGS); \
	fi

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

e2e: build
	@curl -sf -m 5 http://localhost:11434/api/tags >/dev/null || { \
		echo "e2e: Ollama not reachable at localhost:11434 — start Ollama first"; exit 1; }; \
	MODEL="$${LTM_E2E_MODEL:-}"; \
	if [ -z "$$MODEL" ]; then \
		MODEL="$$(python3 scripts/pick-ollama-chat-model.py)"; \
	fi; \
	[ -n "$$MODEL" ] || { echo "e2e: no chat-capable Ollama model installed — pull one or set LTM_E2E_MODEL"; exit 1; }; \
	curl -sf -m 10 http://localhost:11434/api/show -d "{\"model\":\"$$MODEL\"}" >/dev/null || { \
		echo "e2e: model '$$MODEL' not available — 'ollama pull $$MODEL' or set LTM_E2E_MODEL"; exit 1; }; \
	APP="$$(xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe -showBuildSettings 2>/dev/null | \
		awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{d=$$2} / FULL_PRODUCT_NAME =/{p=$$2} END{print d"/"p}')"; \
	test -d "$$APP" && echo "e2e: app bundle present ($$APP)" || { echo "e2e: app bundle missing"; exit 1; }; \
	echo "e2e: LLM contract model = $$MODEL"; \
	LTM_E2E=1 LTM_E2E_MODEL="$$MODEL" swift test --filter OllamaContractE2ETests; \
	echo "e2e checks passed (build + app bundle + real Ollama LLM contract: $$MODEL)"

# Build, optionally sign+notarize, and package a distributable .dmg into dist/.
# Reads signing/notary credentials from the environment; degrades to an UNSIGNED
# dmg (with a warning) when DEVELOPER_ID_APP is unset. See docs/RELEASING.md.
release:
	bash scripts/release.sh
