# Agent Guide

This repository contains the Fall Guardian assisted user Flutter mobile app.

Also follow the workspace-level guide at `../AGENTS.md` when working from the parent folder.

`CLAUDE.md` must stay a thin pointer to this file.

## Project

- Flutter app for the assisted user phone experience
- Owns assisted user alert orchestration, watch communication, emergency contacts, and API interaction from the phone
- Keep widgets UI-only and keep workflow logic in services/coordinators

## Engineering Rules

Always:

- keep cross-platform contracts aligned with the backend, Wear OS app, watchOS app, and caregiver app
- keep generated Flutter/iOS/Android files out of Git unless they are intentionally source-controlled by Flutter
- run `flutter analyze` after Dart changes when feasible
- run `flutter test` for behavior changes when tests exist or are added

Ask first:

- adding Flutter packages or native plugins
- changing bundle IDs, Firebase config, signing, entitlements, or deployment targets
- changing backend API contracts or alert workflow behavior

Never:

- hardcode API secrets, tokens, or production-only local values
- put workflow logic directly in Flutter widgets

## Verification

Common commands:

```sh
flutter analyze
flutter test
```
