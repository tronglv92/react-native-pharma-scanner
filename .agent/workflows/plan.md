---
description: Plan the implementation of a feature or fix — design the approach before writing any code
name: /plan
argument-hint: [feature-name-or-description]
---

# React Native PharmaScanner — Planning Workflow

## Purpose

Design a complete, ordered implementation plan for any feature or fix.
This workflow produces a task list — **no code is written** during planning.

---

## MCP Tool Usage Rules

Apply these rules throughout every planning session:

### Skills
- Always check available skills before starting any task
- Load relevant skills (`systematic-debugging`, `writing-plans`, etc.)

### Token Budget — Task Classification

Classify each task before choosing a planning depth. Wrong choice wastes tokens.

| Task type | Examples | Planning depth |
|---|---|---|
| **Mechanical** | Add a new type to `types.nitro.ts`, update a style, add a button | Write plan directly — skip Plan subagent |
| **Standard** | New native method (both platforms), new UI screen, new camera feature | 1 Explore + write plan directly |
| **Complex** | New native framework integration, cross-platform architecture, real-time processing pipeline | 1–2 Explore + 1 Plan subagent |

### Exploration Strategy
- **First choice:** Glob/Grep/Read tools for targeted file lookup
- **Second choice:** 1 Explore subagent with a focused prompt
- **Avoid:** Multiple parallel Explore agents unless the task genuinely spans unrelated areas

---

## Project Architecture

### Tech Stack
- **JS Layer:** React Native 0.85 + TypeScript 5.8
- **Bridge:** Nitro Modules (react-native-nitro-modules) — HybridObject pattern
- **iOS Native:** Swift (AVFoundation, Vision, VisionKit, ML Kit)
- **Android Native:** Kotlin (CameraX, ML Kit, Play Services)
- **Code Gen:** Nitrogen CLI generates C++/Swift/Kotlin bindings from TypeScript specs
- **Build:** Metro (JS), Xcode + CocoaPods (iOS), Gradle + CMake (Android)

### Key Directories

| Directory | Purpose |
|-----------|---------|
| `src/specs/` | Nitro interface definitions (source of truth for API) |
| `src/` | TypeScript/React components and exports |
| `ios/` | iOS Swift native implementations |
| `pharmascanner/src/main/java/.../PharmaScanner/` | Android Kotlin native implementations |
| `nitrogen/generated/` | Auto-generated bridge code (do not edit) |
| `ios/nitrogen/generated/` | iOS-specific auto-generated code (do not edit) |
| `App.tsx` | Demo/test app UI |

### Implementation Flow (Spec → Native)
```
types.nitro.ts → PharmaScanner.nitro.ts → nitrogen codegen → HybridPharmaScanner.swift / .kt
```

---

## Step 1: Load Context

1. Read existing Nitro specs to understand the current API surface:
   - `src/specs/types.nitro.ts` — all shared types
   - `src/specs/PharmaScanner.nitro.ts` — HybridObject interface
2. Read the platform file relevant to the task:
   - iOS: `ios/HybridPharmaScanner.swift` + related native files
   - Android: `pharmascanner/.../HybridPharmaScanner.kt` + related native files
3. Read `App.tsx` if the task involves UI changes

---

## Step 2: Identify Scope

For the task, determine:

| Item | How to find |
|------|-------------|
| New types needed? | Check `src/specs/types.nitro.ts` |
| New methods needed? | Check `src/specs/PharmaScanner.nitro.ts` |
| iOS implementation | `ios/*.swift` (HybridPharmaScanner + feature files) |
| Android implementation | `pharmascanner/.../PharmaScanner/*.kt` |
| Xcode project update | `ios/ReactNativePharmaScanner.xcodeproj/project.pbxproj` |
| Android dependencies | `pharmascanner/build.gradle` |
| JS/UI changes | `App.tsx`, `src/*.tsx` |

If the feature adds **new native methods**, plan changes across all layers.
If **modifying existing behavior**, read the current implementation on both platforms first.

---

## Step 3: API Contract Design

When the task involves new or modified native methods:

### 3.1 Define Types

Plan new types for `src/specs/types.nitro.ts`:
- Use TypeScript interfaces with `'kotlin'` and `'swift'` language tags
- Follow existing patterns: `interface X extends HybridObject<{...}>` for objects, plain interfaces for structs
- Enums use string union types: `type Foo = 'BAR' | 'BAZ'`

### 3.2 Define Methods

Plan new methods for `src/specs/PharmaScanner.nitro.ts`:
- Sync methods: `methodName(): ReturnType`
- Async methods: `methodName(): Promise<ReturnType>`
- Callbacks: `setOnX(callback: (result: Type) => void): void`

### 3.3 Platform Mapping

For each new method, plan the native implementation:

| Method | iOS (Swift) | Android (Kotlin) |
|--------|-------------|-------------------|
| `newMethod()` | Framework/API to use | Framework/API to use |

### 3.4 Checklist before Step 4

- [ ] Types fully defined with all fields
- [ ] Method signatures match between spec and native capabilities
- [ ] Return types are serializable (no native-only objects)
- [ ] Callback patterns consistent with existing ones
- [ ] Both platforms can implement the feature (or plan platform-specific handling)

---

## Step 4: Design Implementation Structure

Plan files to create or modify, in dependency order:

### Layer 1 — Nitro Specs (API contract)
```
src/specs/types.nitro.ts         — new types/enums
src/specs/PharmaScanner.nitro.ts — new methods on HybridObject
```

### Layer 2 — Code Generation
```
Run: npx nitro-codegen
Output: nitrogen/generated/**, ios/nitrogen/generated/**
```

### Layer 3 — iOS Native Implementation
```
ios/{FeatureName}.swift                    — new feature module
ios/HybridPharmaScanner.swift              — wire new methods
ios/ReactNativePharmaScanner.xcodeproj/    — add new files to Xcode
```

Conventions:
- One Swift file per feature (e.g., `DocumentDetector.swift`, `BarcodeScanner.swift`)
- `HybridPharmaScanner.swift` delegates to feature classes
- Camera-related features go through `CameraManager.shared`
- New files must be added to `project.pbxproj` (PBXBuildFile, PBXFileReference, group children, PBXSourcesBuildPhase)

### Layer 4 — Android Native Implementation
```
pharmascanner/src/main/java/.../PharmaScanner/{FeatureName}.kt
pharmascanner/src/main/java/.../PharmaScanner/HybridPharmaScanner.kt
pharmascanner/build.gradle  (if new dependencies needed)
```

Conventions:
- One Kotlin file per feature (e.g., `DocumentScannerManager.kt`, `BarcodeScannerManager.kt`)
- `HybridPharmaScanner.kt` delegates to feature classes
- ML Kit features use Play Services dependencies
- Camera features go through `CameraManager`

### Layer 5 — JavaScript / UI
```
src/index.ts                — update exports if needed
src/{Component}.tsx          — new React components
App.tsx                      — demo UI updates
```

### Layer 6 — Build Configuration (if needed)
```
ios/Podfile                  — new CocoaPods dependencies
pharmascanner/build.gradle   — new Gradle dependencies
```

---

## Step 5: Implementation Task List

Produce an ordered task list:

```
### Task {N}: {Title}
File:    {exact path to create or modify}
Action:  {create | modify | generate}
Notes:   {dependencies, gotchas, or platform-specific details}
```

**Standard task order:**
1. Add/update types in `types.nitro.ts`
2. Add/update methods in `PharmaScanner.nitro.ts`
3. Run nitrogen codegen
4. Implement iOS native code
5. Add new iOS files to `project.pbxproj`
6. Implement Android native code
7. Update Android `build.gradle` if needed
8. Update JS exports and UI
9. Build and test both platforms

---

## Step 6: Risk Assessment

Identify potential issues:

- **Platform parity**: Can both iOS and Android implement this feature?
- **Permissions**: Does the feature need new permissions (camera, storage, etc.)?
- **Framework availability**: Minimum iOS/Android version for the API being used?
- **Performance**: Is real-time processing needed? Frame rate considerations?
- **Generated code conflicts**: Will nitrogen codegen break existing generated files?
- **Xcode project**: Are new files properly referenced in `project.pbxproj`?
- **Dependencies**: Do new CocoaPods/Gradle dependencies conflict with existing ones?

---

## Step 7: Plan Output

```markdown
# Plan: {Feature Name}

## Scope
{new feature | modify existing | bug fix}

## API Changes
- New types: {list}
- New methods: {list}
- Modified methods: {list}

## Files to Create
- {path} — {purpose}

## Files to Modify
- {path} — {what changes and why}

## Tasks (ordered)
1. {task}
2. {task}
...

## Platform Details
- iOS: {frameworks/APIs used}
- Android: {libraries/APIs used}

## Risks
- {risk and mitigation}
```

**Next step:** Review and approve, then run `/execute`.

---

## Constraints

- **No code** — produce plan and task list only
- **Spec first** — always plan Nitro spec changes before native implementation
- **Read before planning** — always read existing files before planning changes
- **Both platforms** — every new method needs implementation on iOS and Android
- **Minimal scope** — plan only what is needed for the task
- **Never edit generated files** — files in `nitrogen/generated/` and `ios/nitrogen/generated/` are auto-generated
