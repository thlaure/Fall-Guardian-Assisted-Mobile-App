.PHONY: help install format analyze test check build-android build-ios clean

.DEFAULT_GOAL := help

help: ## Show available commands
	@echo "Fall Guardian assisted app"
	@echo ""
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Install Flutter dependencies
	flutter pub get

format: ## Format Dart source and tests
	dart format lib/ test/

analyze: ## Run Flutter static analysis
	flutter analyze

test: ## Run Flutter tests
	flutter test

check: format test analyze ## Format, test, and analyze

build-android: ## Build Android debug APK
	flutter build apk --debug

build-ios: ## Build iOS simulator app
	flutter build ios --simulator --debug

clean: ## Clean Flutter build artifacts
	flutter clean
