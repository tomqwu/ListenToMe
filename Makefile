.PHONY: gen build test lint run pre-push e2e release

SHELL := /bin/bash
.SHELLFLAGS := -eo pipefail -c

# Optional local signing override (gitignored) — define SIGN_FLAGS for a stable identity
# so granted macOS permissions (TCC) persist across rebuilds. See signing.local.mk.example.
-include signing.local.mk

gen:
	xcodegen generate
	mkdir -p ListenToMe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
	cp Config/Package.resolved ListenToMe.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

build: gen
	@if command -v xcbeautify >/dev/null 2>&1; then \
		xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe \
			-destination 'platform=macOS' -configuration Debug -onlyUsePackageVersionsFromResolvedFile build $(SIGN_FLAGS) | xcbeautify; \
	else \
		xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe \
			-destination 'platform=macOS' -configuration Debug -onlyUsePackageVersionsFromResolvedFile build $(SIGN_FLAGS); \
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

pre-push: bdd-check lint test build
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
	LTM_E2E=1 LTM_E2E_MODEL="$$MODEL" python3 scripts/run-contract-tests.py OllamaContractE2ETests && \
	echo "e2e: OpenAI-compatible contract via Ollama's /v1 API" && \
	LTM_E2E=1 LTM_E2E_MODEL="$$MODEL" python3 scripts/run-contract-tests.py OpenAICompatibleContractE2ETests && \
	echo "e2e checks passed (build + app bundle + real Ollama and OpenAI-compatible LLM contracts: $$MODEL)"

# Build, optionally sign+notarize, and package a distributable .dmg into dist/.
# Reads signing/notary credentials from the environment; degrades to an UNSIGNED
# dmg (with a warning) when DEVELOPER_ID_APP is unset. See docs/RELEASING.md.
release:
	bash scripts/release.sh

# iPhone/iPad target (iOS 26+). Override IOS_DESTINATION with a connected device/simulator.
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro
IOS_SIGN_FLAGS ?= CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-

.PHONY: ios-build ios-test ios-archive watch-build
# The iOS scheme builds and embeds its Apple Watch companion (#181).
ios-build: gen
	xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeIOS -configuration Debug \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios \
		-onlyUsePackageVersionsFromResolvedFile $(IOS_SIGN_FLAGS) build

watch-build: gen
	xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeWatch -configuration Debug \
		-destination 'generic/platform=watchOS Simulator' -derivedDataPath .build/ios \
		-onlyUsePackageVersionsFromResolvedFile $(IOS_SIGN_FLAGS) build

ios-test: gen
	mkdir -p dist/bdd
	xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeIOS -configuration Debug \
		-destination '$(IOS_DESTINATION)' -derivedDataPath .build/ios \
		-onlyUsePackageVersionsFromResolvedFile $(IOS_SIGN_FLAGS) -parallel-testing-enabled NO test | tee dist/bdd/ios-full.log
	python3 scripts/bdd.py --verify-log ios-unit dist/bdd/ios-full.log
	python3 scripts/bdd.py --verify-log ios-ui dist/bdd/ios-full.log

.PHONY: mac-test watch-test
mac-test: gen
	mkdir -p dist/bdd
	xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeMacTests -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath .build/mac-native-tests \
		-onlyUsePackageVersionsFromResolvedFile $(IOS_SIGN_FLAGS) -parallel-testing-enabled NO test | tee dist/bdd/mac-full.log
	python3 scripts/bdd.py --verify-log mac-unit dist/bdd/mac-full.log

watch-test: gen
	@case '$(WATCH_DESTINATION)' in 'platform=watchOS Simulator,id='*) ;; \
		*) echo 'Set WATCH_DESTINATION to a dedicated watchOS Simulator id'; exit 2 ;; esac
	mkdir -p dist/bdd
	xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeWatchTests -configuration Debug \
		-destination '$(WATCH_DESTINATION)' -derivedDataPath .build/watch-native-tests \
		-onlyUsePackageVersionsFromResolvedFile $(IOS_SIGN_FLAGS) -parallel-testing-enabled NO test | tee dist/bdd/watch-full.log
	python3 scripts/bdd.py --verify-log watch-unit dist/bdd/watch-full.log
	python3 scripts/bdd.py --verify-log watch-ui dist/bdd/watch-full.log

ios-archive: gen
	xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMeIOS -configuration Release \
		-destination 'generic/platform=iOS' -archivePath dist/ListenToMe-iOS.xcarchive \
		-derivedDataPath .build/ios-release -onlyUsePackageVersionsFromResolvedFile -allowProvisioningUpdates archive

# Upload a validated archive; source/CI checks and tester verification are in docs/IOS-RELEASING.md.
export IOS_EXPORT_OPTIONS
.PHONY: ios-testflight
ios-testflight:
	@test -n "$(IOS_ARCHIVE)" -a -n "$(IOS_RELEASE_SOURCE)" || { echo 'Set IOS_ARCHIVE and IOS_RELEASE_SOURCE'; exit 2; }
	bash scripts/ios-testflight.sh "$(IOS_ARCHIVE)" "$(IOS_RELEASE_SOURCE)" $(IOS_RELEASE_FLAGS)

# Complete automated validation (GUI/audio/device/e2e) runs locally; GitHub Actions builds both app
# targets and separately runs the headless ListenToMeCore tests + coverage floor (see ci.yml's
# `core` job, which calls scripts/check-coverage.sh directly rather than this target).
.PHONY: validate-local
validate-local:
	@test "$$(uname -s)" = Darwin || { echo 'Run validation on a local Mac'; exit 1; }
	@test "$${GITHUB_ACTIONS:-false}" != true || { echo 'GUI/audio/device/e2e validation must run locally, not in GitHub Actions'; exit 1; }
	$(MAKE) bdd-check
	python3 scripts/test-bdd.py
	bash -n scripts/ios-testflight.sh
	python3 scripts/test-ios-testflight.py
	python3 scripts/test-contract-gate.py
	bash -n scripts/release.sh scripts/release-paths.sh
	python3 scripts/test-release-paths.py
	bash scripts/test-hotkey.sh
	$(MAKE) lint
	./scripts/check-coverage.sh 95
	$(MAKE) ios-test
	$(MAKE) mac-test
	$(MAKE) watch-test
	$(MAKE) e2e

# Given/When/Then contracts bind directly to native tests; no second test framework.
# Override BDD_BASE for a stacked PR's actual base. The default checks against main.
BDD_BASE ?= origin/main
BDD_SUITE ?= core
ifeq ($(BDD_SUITE),mac-unit)
BDD_DESTINATION ?= platform=macOS
else ifneq ($(filter watch-unit watch-ui,$(BDD_SUITE)),)
BDD_DESTINATION ?= $(WATCH_DESTINATION)
else
BDD_DESTINATION ?= $(IOS_DESTINATION)
endif
.PHONY: bdd-check bdd-test bdd-manual
bdd-check:
	python3 scripts/bdd.py --base '$(BDD_BASE)'

bdd-test: bdd-check
	python3 scripts/bdd.py --run '$(BDD_SUITE)' --destination '$(BDD_DESTINATION)'

bdd-manual:
	python3 scripts/bdd.py --manual
