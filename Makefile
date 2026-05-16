.PHONY: help install format format-check analyze test coverage quality check build-android build-ios clean

.DEFAULT_GOAL := help

help: ## Show available commands
	@echo "Fall Guardian assisted app"
	@echo ""
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Install Flutter dependencies
	flutter pub get

format: ## Format Dart source and tests
	dart format lib/ test/

format-check: ## Check Dart formatting without modifying files
	dart format --set-exit-if-changed lib/ test/

analyze: ## Run Flutter static analysis
	flutter analyze

test: ## Run Flutter tests
	flutter test

coverage: ## Run Flutter tests with coverage output
	flutter test --coverage

quality: format-check analyze coverage ## Run deterministic quality checks

check: quality ## Run the default verification set

build-android: ## Build Android debug APK
	flutter build apk --debug

build-ios: ## Build iOS simulator app
	flutter build ios --simulator --debug

clean: ## Clean Flutter build artifacts
	flutter clean
