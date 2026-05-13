# Fall Guardian Assisted App

Flutter mobile app for the assisted user. It owns the phone-side fall alert
experience, emergency contacts, local alert countdown, watch communication, and
backend API submission.

## Responsibilities

- receive fall events from supported watches
- keep the phone alert flow explicit and cancellable
- submit escalation events to the backend when an alert is not cancelled
- manage assisted-user emergency contact data
- keep mobile/backend contracts aligned with `fall_guardian_api`

## Requirements

- Flutter SDK compatible with Dart `>=3.0.0 <4.0.0`
- Android Studio or Xcode for platform builds
- backend API available locally or remotely

## Setup

```sh
flutter pub get
```

## Verification

```sh
flutter analyze
flutter test
```

Run platform builds from this repo when changing native Android or iOS code.

## Related Repositories

- `../fall_guardian_api`: backend API
- `../fall_guardian_caregiver_app`: caregiver mobile app
- `../fall_guardian_wear_os_app`: Wear OS watch app
- `../fall_guardian_watchos_app`: watchOS app
