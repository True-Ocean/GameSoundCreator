# GameSoundCreator validation

Run from the repository root unless noted otherwise.

## Static checks

```sh
git diff --check
git status --short
```

## iOS build

```sh
xcodebuild -project GameSoundCreator.xcodeproj -scheme GameSoundCreator -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Use the real device destination only when installation or hardware behavior must be checked.

## Core tests

Run from `Packages/AudioGenCore`.

```sh
swift test
```

For changes to generation ordering, also run:

```sh
swift test --filter AudioGenCoreTests/testNewerGenerationWinsWhenOlderBackgroundSynthesisCompletes
```

## Real-device checks

Require an iPhone check for changes touching these paths:

- Start BGM and SFX playback; change BGM controls while playing; try a different pattern.
- Export BGM and SFX and confirm the share sheet and current settings are reflected.
- While playing, trigger an audio interruption or disconnect the Bluetooth output; confirm playback stops and the UI recovers.
- Start library playback, stop it, enter delete mode while playing, and leave the screen during BGM generation.

Report exact steps and wait for the user's confirmation before declaring the affected step complete.
