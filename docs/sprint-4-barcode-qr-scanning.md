# Sprint 4 — Barcode / QR Scanning

## Context

The PharmaScanner module currently supports camera capture and document detection. This sprint adds barcode/QR scanning for pharmacy-relevant formats (medication packaging, labels). Two modes are needed: one-shot scanning from still images and continuous real-time scanning from the camera feed.

## New Types (`src/specs/types.nitro.ts`)

Append after `DocumentDetection`:

```typescript
export type BarcodeFormat = 'QR_CODE' | 'CODE_128' | 'PDF_417' | 'DATA_MATRIX' | 'EAN_13' | 'EAN_8';

export interface FrameRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface BarcodeResult {
  format: BarcodeFormat;
  value: string;
  rawValue: string;
  boundingBox?: FrameRect;
}

export interface BarcodeScanOptions {
  imageUri: string;
  formats: BarcodeFormat[];
}
```

## New Methods (`src/specs/PharmaScanner.nitro.ts`)

Add imports for `BarcodeScanOptions`, `BarcodeResult`, `BarcodeFormat` and append to the interface:

```typescript
scanBarcodes(options: BarcodeScanOptions): Promise<BarcodeResult[]>;
startContinuousScan(formats: BarcodeFormat[], onDetected: (codes: BarcodeResult[]) => void): void;
stopContinuousScan(): void;
```

## Update Exports (`src/index.ts`)

Add `BarcodeFormat`, `BarcodeScanOptions`, `BarcodeResult`, `FrameRect` to the type re-export line.

## Code Generation

Run `npx nitrogen` to regenerate all `nitrogen/generated/` files. This produces:
- C++ enums, structs, JSI converters for all new types
- Updated Swift protocol + Kotlin abstract class with the 3 new methods
- Callback wrapper for `(BarcodeResult[]) => void`

## iOS Implementation

### New file: `ios/BarcodeScanner.swift`

Handles still-image barcode scanning using `VNDetectBarcodesRequest` (Vision framework).

- `scanBarcodes(imageUri:formats:) async throws -> [BarcodeResult]` — loads image via `CIImage(contentsOf:)`, runs `VNDetectBarcodesRequest` with mapped symbologies, returns results
- Format mapping helpers: `BarcodeFormat` <-> `VNBarcodeSymbology` and `AVMetadataObject.ObjectType`
- No new dependencies needed — Vision and AVFoundation are already used

### Modify: `ios/CameraManager.swift`

Add `AVCaptureMetadataOutput` for real-time barcode detection (hardware-accelerated, separate from existing video output pipeline):

- New properties: `metadataOutput`, `metadataProcessingQueue`, `onBarcodesDetectedCallback`, `continuousScanFormats`
- `startContinuousScan(formats:)` — adds metadata output to capture session, sets `metadataObjectTypes`, sets delegate
- `stopContinuousScan()` — removes metadata output, clears callback
- `AVCaptureMetadataOutputObjectsDelegate` extension — maps `AVMetadataMachineReadableCodeObject` to `BarcodeResult`, invokes callback
- Update `stopSession()` to clean up barcode state
- Add simulator guards (metadata output unavailable on simulator)

### Modify: `ios/HybridPharmaScanner.swift`

Add 3 method implementations following existing patterns:
- `scanBarcodes(options:)` — `Promise.async { }` wrapping `BarcodeScanner.scanBarcodes()`
- `startContinuousScan(formats:onDetected:)` — stores callback on `cameraManager`, calls `startContinuousScan`
- `stopContinuousScan()` — delegates to `cameraManager.stopContinuousScan()`

### Xcode project

Add `BarcodeScanner.swift` to the ReactNativePharmaScanner target in `project.pbxproj`.

## Android Implementation

### New dependency (`pharmascanner/build.gradle`)

```gradle
implementation "com.google.mlkit:barcode-scanning:17.3.0"
```

### New file: `pharmascanner/.../BarcodeScannerManager.kt`

Singleton object for still-image barcode scanning:

- `scanBarcodes(options: BarcodeScanOptions): Array<BarcodeResult>` — suspend function, creates ML Kit `BarcodeScanner` with mapped formats, processes `InputImage.fromFilePath()`, wraps with `suspendCoroutine`
- Format mapping: `BarcodeFormat` <-> ML Kit `Barcode.FORMAT_*` constants
- `mapBarcodeToResult()` — shared helper for both still and continuous scanning
- Holds `onBarcodesDetectedCallback` and `activeFormats` for continuous mode

### Modify: `pharmascanner/.../CameraManager.kt`

Add `ImageAnalysis` use case for continuous barcode scanning:

- New properties: `imageAnalysis`, `isContinuousScanActive`, `continuousScanFormats`
- Add `ImageAnalysis` creation in `startSession()` and include it in `bindToLifecycle()` (3 use cases: Preview + ImageCapture + ImageAnalysis)
- `startContinuousScan(formats:)` — creates ML Kit scanner with specified formats, sets analyzer on `imageAnalysis` using `backgroundExecutor`
- `stopContinuousScan()` — clears analyzer, resets callback
- `processBarcode(imageProxy, scanner)` — `@ExperimentalGetImage`, creates `InputImage.fromMediaImage()`, processes with ML Kit, invokes callback, closes `imageProxy`
- Update `stopSession()` to clean up barcode state

### Modify: `pharmascanner/.../HybridPharmaScanner.kt`

Add 3 method implementations:
- `scanBarcodes(options:)` — `Promise.async { BarcodeScannerManager.scanBarcodes(options) }`
- `startContinuousScan(formats, onDetected)` — stores callback, delegates to `CameraManager`
- `stopContinuousScan()` — delegates to `CameraManager`

## Files Summary

| File | Action |
|------|--------|
| `src/specs/types.nitro.ts` | Modify — add 4 types |
| `src/specs/PharmaScanner.nitro.ts` | Modify — add 3 methods + imports |
| `src/index.ts` | Modify — add type exports |
| `nitrogen/generated/**` | Regenerate via codegen |
| `ios/BarcodeScanner.swift` | **Create** |
| `ios/CameraManager.swift` | Modify — add metadata output + continuous scan |
| `ios/HybridPharmaScanner.swift` | Modify — add 3 methods |
| `ios/...project.pbxproj` | Modify — add file reference |
| `pharmascanner/build.gradle` | Modify — add ML Kit dependency |
| `pharmascanner/.../BarcodeScannerManager.kt` | **Create** |
| `pharmascanner/.../CameraManager.kt` | Modify — add ImageAnalysis + continuous scan |
| `pharmascanner/.../HybridPharmaScanner.kt` | Modify — add 3 methods |

## Verification

1. `npx nitrogen` completes without errors
2. `npx tsc --noEmit` passes
3. iOS: `cd ios && pod install` then `npx react-native run-ios` builds
4. Android: `npx react-native run-android` builds
5. Test `scanBarcodes()` — capture a photo of a QR code, scan it, verify result contains correct value
6. Test `startContinuousScan()` — start camera, start continuous scan, point at barcode, verify callback fires with results
7. Test `stopContinuousScan()` — verify callbacks stop firing
8. Edge cases: call stop before start (safe no-op), call with empty formats, test on simulator/emulator
