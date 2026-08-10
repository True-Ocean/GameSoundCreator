---
name: game-sound-safe-refactor
description: Review, plan, and safely improve the GameSoundCreator iOS/Swift codebase. Use when asked to audit code quality or bugs, create a remediation plan, implement fixes incrementally, verify audio-generation or playback changes, perform a strict post-change review, or prepare an approved commit in this repository.
---

# Game Sound Safe Refactor

Use this workflow for code review and fixes in this repository. Preserve unrelated user changes and keep every implementation step independently reviewable.

## 1. Establish the baseline

1. Read repository instructions and inspect `git status --short`.
2. Treat existing changes as user-owned unless they clearly belong to the active task.
3. For a review-only request, do not edit code. Report findings by severity, evidence, impact, and a concrete remediation.
4. Inspect both app code and `Packages/AudioGenCore` when a workflow crosses UI, generation, playback, export, or persistence.

## 2. Plan before broad fixes

1. Group findings into independent, reversible steps.
2. Start with correctness and data-loss risks, then concurrency/playback lifecycle issues, then structure and testability.
3. State the expected verification for every step.
4. Do not mix unrelated refactors, behavior changes, and formatting churn in one step.

## 3. Implement exactly one step

1. Make the smallest coherent change for the current step.
2. Use stable request IDs or task cancellation where newer audio work can supersede older work.
3. Keep audio generation off the main actor when the core API supports it.
4. Keep SwiftUI views responsible for presentation; move service-facing workflow and task ownership into focused observable models when practical.
5. Run `git diff --check`, inspect the relevant diff, then use the applicable checks in [references/project-validation.md](references/project-validation.md).
6. If the behavior depends on AVAudioSession, device routing, sharing, or real playback, stop after automated checks and give concise iPhone test steps. Do not proceed until the user confirms the result or explicitly directs otherwise.

## 4. Review each completed step

Check at least the following before moving on:

- Cancellation cannot let an older operation clear newer UI state or publish stale audio.
- UI busy/overlay state matches the lifetime of the corresponding task.
- Interruption or route-change handling does not cancel unrelated save/export work.
- Export uses the current visible controls and does not overwrite an existing file.
- Persistence failures leave in-memory library state consistent and corrupt data is recoverable.

Report any residual risk immediately. Fix it as its own next step rather than silently broadening the current change.

## 5. Commit and final handoff

1. Commit only when the user explicitly requests it.
2. Before staging, list changed files, verify they are in scope, and run `git diff --check`.
3. After committing, confirm the commit ID and clean worktree.
4. On completion, provide a strict final review summary, the checks that passed, any checks not run, and remaining risks.

## Project checks

Read [references/project-validation.md](references/project-validation.md) before running automated or real-device verification.
