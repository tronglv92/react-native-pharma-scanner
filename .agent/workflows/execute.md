---
description: Execute an implementation plan — build feature, validate, and finalize
name: /execute
argument-hint: [feature-name-or-plan]
---

# React Native PharmaScanner — Execution Workflow

## MCP Tool Usage Rules

Apply these rules throughout every execution session:

### Skills
- Always check available skills before starting — load `systematic-debugging` for bugs, `test-driven-development` for features
- Never skip skill loading to save time — skills prevent rework

### Token Budget — Task Classification

Classify each task before choosing a review strategy.

| Task type | Examples | Review strategy |
|---|---|---|
| **Mechanical** | Generated code, type definitions, config changes, style updates | 1 implementer → build check → commit. No reviewers. |
| **Standard** | New native method, UI component, single-platform feature | 1 implementer → build check → commit |
| **Complex** | Multi-platform feature, real-time processing, new framework integration | Full pipeline: explore → implement → build both platforms → verify |

**For exploration:** Use Glob/Grep/Read tools first. Only spawn an Explore subagent if targeted search cannot answer the question.

**For planning:** Skip the Plan subagent when the task spec already defines exact file contents. Plan subagents are for tasks requiring design judgment.

### Security Rules
- Never hardcode API keys, tokens, secrets, or credentials in native or JS code
- Camera and storage permissions must be declared in Info.plist / AndroidManifest.xml
- Validate all inputs at the native bridge boundary

---

## Step 0: Plan Activation

1. Load the plan (from `/plan` output or user instructions)
2. Confirm target files exist; check current state of files to be modified
3. Check git branch is correct before writing any file
4. Identify which layers need changes: spec → codegen → iOS → Android → JS/UI

---

## Step 1: Pre-Implementation Checks

Before writing code:

- [ ] Current Nitro specs reviewed (`src/specs/types.nitro.ts`, `src/specs/PharmaScanner.nitro.ts`)
- [ ] Existing native implementations reviewed (iOS and/or Android)
- [ ] No conflicting implementation already exists
- [ ] Required frameworks/libraries available on target platform versions
- [ ] iOS deployment target supports the APIs being used
- [ ] Android minSdk supports the libraries being used

---

## Step 2: Implementation Order (MANDATORY — follow strictly)

### 2.1 Nitro Specs (if API changes needed)

Update the TypeScript spec files — these are the source of truth.

**Types** — `src/specs/types.nitro.ts`:
```typescript
// Enums use string unions
export type NewEnum = 'VALUE_A' | 'VALUE_B'

// Structs use interfaces
export interface NewStruct {
  field1: string
  field2: number
  optionalField?: string
}
```

**Methods** — `src/specs/PharmaScanner.nitro.ts`:
```typescript
interface PharmaScanner extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  // Sync
  newSyncMethod(): string
  // Async
  newAsyncMethod(param: string): Promise<ResultType>
  // Callback
  setOnNewEvent(callback: (result: EventType) => void): void
}
```

### 2.2 Code Generation (if specs changed)

```bash
npx nitro-codegen
```

This regenerates:
- `nitrogen/generated/` — shared C++, Android Kotlin/C++, iOS Swift
- `ios/nitrogen/generated/` — iOS-specific bridges

**Never manually edit generated files.**

### 2.3 iOS Native Implementation

#### New feature file — `ios/{FeatureName}.swift`:
```swift
import Foundation
// Import required frameworks (Vision, VisionKit, AVFoundation, etc.)

class FeatureName {
  func doSomething() async throws -> ResultType {
    // Implementation using Apple frameworks
  }
}
```

#### Wire into HybridPharmaScanner — `ios/HybridPharmaScanner.swift`:
```swift
class HybridPharmaScanner: HybridPharmaScannerSpec {
  // Add property to retain the feature manager
  private let featureManager = FeatureName()

  // Implement the spec method
  func newMethod() throws -> Promise<ResultType> {
    return Promise.async {
      return try await self.featureManager.doSomething()
    }
  }
}
```

#### Add to Xcode project — `project.pbxproj`:

Three additions needed:
1. **PBXBuildFile section**: `{ID_AA} /* File.swift in Sources */ = {isa = PBXBuildFile; fileRef = {ID_BB} /* File.swift */; };`
2. **PBXFileReference section**: `{ID_BB} /* File.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = File.swift; sourceTree = "<group>"; };`
3. **PBXGroup children**: Add `{ID_BB}` to the ReactNativePharmaScanner group
4. **PBXSourcesBuildPhase files**: Add `{ID_AA}` to the Sources build phase

Use the existing ID pattern: `FA{X}00001{X}00000000000{AA|BB}XX` where X is the sprint/feature number.

### 2.4 Android Native Implementation

#### New feature file — `pharmascanner/src/main/java/.../PharmaScanner/{FeatureName}.kt`:
```kotlin
package com.margelo.nitro.PharmaScanner

class FeatureName(private val context: Context) {
  suspend fun doSomething(): ResultType {
    // Implementation using ML Kit / CameraX / etc.
  }
}
```

#### Wire into HybridPharmaScanner — `HybridPharmaScanner.kt`:
```kotlin
class HybridPharmaScanner : HybridPharmaScannerSpec() {
  override fun newMethod(): Promise<ResultType> {
    return Promise.async {
      featureManager.doSomething()
    }
  }
}
```

#### Dependencies — `pharmascanner/build.gradle` (if needed):
```groovy
dependencies {
  implementation 'com.google.mlkit:new-library:version'
}
```

### 2.5 JavaScript / UI Layer

#### Update exports — `src/index.ts` (if new types exported):
```typescript
export type { NewType } from './specs/types.nitro.ts'
```

#### Update demo UI — `App.tsx`:
- Add buttons/controls for the new feature
- Handle async results with proper loading/error states
- Follow existing patterns: `useState` for state, `try/catch` for errors, `Alert.alert` for messages

### 2.6 Build Configuration (if needed)

- **iOS**: Update `ios/Podfile` for new CocoaPods dependencies, run `pod install`
- **Android**: Update `pharmascanner/build.gradle` for new Gradle dependencies

---

## Step 3: Code Quality Rules

### Swift (iOS)
- Use `async/await` for asynchronous operations
- Use `withCheckedThrowingContinuation` to bridge delegate-based APIs to async
- Retain delegate objects as properties (not local variables)
- Use `DispatchQueue.main.async` for UI operations from background threads
- Present view controllers via the topmost presented controller
- Save images to `FileManager.default.temporaryDirectory`
- Use static properties for expensive objects (e.g., `CIContext`)

### Kotlin (Android)
- Use coroutines (`suspend fun`) for async operations
- Use `ActivityResultLauncher` for activity-based APIs
- ML Kit tasks: use `await()` from kotlinx-coroutines-play-services
- Camera operations go through CameraManager
- Save images to `context.cacheDir`

### TypeScript / React
- Use functional components with hooks
- Handle all Promise rejections with try/catch
- Clean up subscriptions/callbacks in useEffect return
- Use `useRef` for values that shouldn't trigger re-renders
- Use `useCallback` for stable callback references

### Cross-Platform
- All native methods must be implemented on both platforms
- Return types must match exactly between platforms
- Use normalized coordinates (0-1) for geometry, not pixel values
- Image URIs should use `file://` scheme
- Callbacks should be settable and clearable

---

## Step 4: Validation

### 4.1 iOS Build

```bash
cd ios && xcodebuild -workspace ReactNativePharmaScanner.xcworkspace \
  -scheme ReactNativePharmaScanner \
  -configuration Debug \
  -sdk iphonesimulator \
  build 2>&1 | tail -20
```

Fix all compilation errors before proceeding.

### 4.2 Android Build

```bash
cd android && ./gradlew assembleDebug 2>&1 | tail -20
```

Fix all compilation errors before proceeding.

### 4.3 TypeScript Check

```bash
npx tsc --noEmit
```

### 4.4 Lint

```bash
npx eslint . --ext .ts,.tsx
```

### 4.5 Manual Checklist

- [ ] iOS builds with zero errors
- [ ] Android builds with zero errors
- [ ] TypeScript compiles with no type errors
- [ ] New iOS files added to `project.pbxproj`
- [ ] New Android dependencies added to `build.gradle`
- [ ] Generated code regenerated if specs changed (`npx nitro-codegen`)
- [ ] Nitro spec types match native implementations
- [ ] Both platforms implement all new methods
- [ ] No hardcoded credentials or secrets
- [ ] Camera/storage permissions declared if needed
- [ ] Demo UI updated in `App.tsx` for testability

---

## Step 5: Summary

```
=== Execution Complete ===

Feature:  {name}
Platform: {iOS | Android | Both}

Files created:
  - {path} — {purpose}

Files modified:
  - {path} — {what changed}

Spec changes:
  - New types: {list or "none"}
  - New methods: {list or "none"}

Validation:
  - iOS build:     [pass/fail]
  - Android build: [pass/fail]
  - TypeScript:    [pass/fail]

Next steps:
  - {any remaining work}
```

---

## Execution Rules

1. **Spec first** — if the feature changes the API, update Nitro specs before native code
2. **Codegen before native** — run `npx nitro-codegen` after spec changes, before implementing
3. **Both platforms** — every new method needs iOS (Swift) and Android (Kotlin) implementations
4. **Xcode project** — every new iOS file must be added to `project.pbxproj`
5. **Never edit generated files** — `nitrogen/generated/` and `ios/nitrogen/generated/` are auto-generated
6. **Retain delegates** — store delegate objects as class properties, not local variables
7. **Async patterns** — use `Promise.async` (Nitro) to bridge Swift `async`/Kotlin coroutines to JS
8. **Minimal changes** — only write files the plan requires; no unsolicited refactoring
9. **Test on device** — real-time camera features cannot be tested in simulator
