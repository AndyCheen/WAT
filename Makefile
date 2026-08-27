SIMULATOR ?= iPhone 16 Pro
SCHEME ?= WaterTracker
# Без цього xcodebuild пише в ~/Library/Developer/Xcode/DerivedData, а тека DerivedData/
# у проєкті лишається зі старою збіркою. Далі `find DerivedData -name '*.app'` віддає
# застарілий бінарник — і в симулятор їде код, якого вже давно немає в репозиторії.
DERIVED ?= DerivedData
PACKAGES := Core Persistence Metrics Hydration Gamification Insights DesignSystem Features

.PHONY: project build install test test-packages test-ui clean

project:
	xcodegen generate

build: project
	xcodebuild build -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-derivedDataPath $(DERIVED) -quiet

## Юніт-тести всіх локальних пакетів (без симулятора — швидкий цикл)
test-packages:
	@for p in $(PACKAGES); do \
		echo "▸ $$p"; \
		swift test --package-path Packages/$$p 2>&1 | grep -E "error:|Executed [0-9]+ tests, with" | tail -2; \
	done

## E2E у симуляторі
test-ui: project
	xcodebuild test -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-derivedDataPath $(DERIVED) -quiet

test: test-packages test-ui

clean:
	rm -rf .build DerivedData WaterTracker.xcodeproj
	@for p in $(PACKAGES); do rm -rf Packages/$$p/.build; done

## Ставить у запущений симулятор саме ту збірку, яку щойно зробив `make build`
install: build
	xcrun simctl install booted "$(DERIVED)/Build/Products/Debug-iphonesimulator/WaterTracker.app"
	xcrun simctl launch booted com.watertracker.app
