SIMULATOR ?= iPhone 16 Pro
SCHEME ?= WaterTracker
PACKAGES := Core Persistence Metrics Hydration Gamification Insights DesignSystem Features

.PHONY: project build test test-packages test-ui clean

project:
	xcodegen generate

build: project
	xcodebuild build -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=$(SIMULATOR)' -quiet

## Юніт-тести всіх локальних пакетів (без симулятора — швидкий цикл)
test-packages:
	@for p in $(PACKAGES); do \
		echo "▸ $$p"; \
		swift test --package-path Packages/$$p 2>&1 | grep -E "error:|Executed [0-9]+ tests, with" | tail -2; \
	done

## E2E у симуляторі
test-ui: project
	xcodebuild test -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=$(SIMULATOR)' -quiet

test: test-packages test-ui

clean:
	rm -rf .build DerivedData WaterTracker.xcodeproj
	@for p in $(PACKAGES); do rm -rf Packages/$$p/.build; done
