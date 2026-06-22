# react-native-pharma-scanner

[![npm version](https://img.shields.io/npm/v/react-native-pharma-scanner.svg)](https://www.npmjs.com/package/react-native-pharma-scanner)
[![npm downloads](https://img.shields.io/npm/dm/react-native-pharma-scanner.svg)](https://www.npmjs.com/package/react-native-pharma-scanner)
[![license](https://img.shields.io/npm/l/react-native-pharma-scanner.svg)](https://github.com/tronglv92/react-native-pharma-scanner/blob/main/LICENSE)

React Native document scanning library with pluggable AI providers for structured data extraction. Supports document detection, OCR, barcode scanning, and AI-powered data extraction from invoices, prescriptions, receipts, and more.

## Features

- Document detection and auto-capture with perspective correction
- OCR text recognition (ML Kit on Android, Vision on iOS)
- Barcode/QR code scanning (QR_CODE, CODE_128, PDF_417, DATA_MATRIX, EAN_13, EAN_8)
- AI-powered structured data extraction with pluggable providers (Mistral, OpenAI, Claude, Local LLM)
- On-device LLM inference via llama.cpp (no API key required)
- Custom document schema support
- Built with [Nitro Modules](https://github.com/nicklockwood/react-native-nitro-modules) for high-performance native bridging

## Requirements

- React Native >= 0.73.0
- React >= 18.0.0
- react-native-nitro-modules >= 0.35.0
- iOS 15.1+
- Android API 24+

## Installation

### Step 1: Install the package

```bash
npm install react-native-pharma-scanner react-native-nitro-modules
# or
yarn add react-native-pharma-scanner react-native-nitro-modules
```

### Step 2: Install iOS dependencies

```bash
cd ios && pod install && cd ..
```

### Step 3: Android setup

No additional setup is required. The library auto-links via React Native CLI.

For local LLM support, the llama.cpp native code is compiled automatically during the Android Gradle build.

## Usage

### Basic setup

```typescript
import { scanner } from 'react-native-pharma-scanner';

// Verify the module is loaded
console.log(scanner.ping());
console.log(scanner.getVersion());
```

### Camera and document scanning

```typescript
import { scanner } from 'react-native-pharma-scanner';

// Start camera
scanner.startCamera();

// Capture a photo
const image = await scanner.capturePhoto();
console.log(image.uri, image.width, image.height);

// Scan a document (auto-detect edges, crop, and correct perspective)
const pages = await scanner.scanDocument();

// Control flash and zoom
scanner.setFlash('auto'); // 'auto' | 'on' | 'off'
scanner.setZoom(1.5);

// Stop camera when done
scanner.stopCamera();
```

### Document detection

```typescript
import { scanner } from 'react-native-pharma-scanner';

// One-shot detection
const detection = await scanner.detectDocument(imageUri);
if (detection.detected) {
  console.log('Corners:', detection.corners);
  console.log('Confidence:', detection.confidence);
}

// Crop and correct perspective
const corrected = await scanner.cropAndCorrect(imageUri, detection.corners);

// Continuous detection callback
scanner.setOnDocumentDetected((detection) => {
  if (detection.isStable) {
    // Document is stable, ready to capture
  }
});
```

### Barcode scanning

```typescript
import { scanner } from 'react-native-pharma-scanner';

// One-shot scan
const barcodes = await scanner.scanBarcodes({
  imageUri: 'file:///path/to/image.jpg',
  formats: ['QR_CODE', 'CODE_128', 'EAN_13'],
});

barcodes.forEach((code) => {
  console.log(code.format, code.value);
});

// Continuous scanning
scanner.startContinuousScan(['QR_CODE', 'EAN_13'], (codes) => {
  codes.forEach((code) => console.log(code.value));
});

// Stop when done
scanner.stopContinuousScan();
```

### OCR (Text Recognition)

```typescript
import { scanner } from 'react-native-pharma-scanner';

const result = await scanner.recognizeText(imageUri);
console.log(result.text);
console.log(`Processed in ${result.processingTimeMs}ms`);

// Access detailed structure
result.blocks.forEach((block) => {
  block.lines.forEach((line) => {
    console.log(line.text, `confidence: ${line.confidence}`);
  });
});
```

### AI-powered document extraction

#### Using cloud providers

```typescript
import {
  extractDocument,
  MistralProvider,
  OpenAIProvider,
  ClaudeProvider,
} from 'react-native-pharma-scanner';

// Choose a provider
const provider = new MistralProvider({ apiKey: 'your-mistral-api-key' });
// or
const provider = new OpenAIProvider({ apiKey: 'your-openai-api-key' });
// or
const provider = new ClaudeProvider({ apiKey: 'your-anthropic-api-key' });

// Extract structured data from a document image
const result = await extractDocument(provider, imageUri, {
  documentType: 'invoice', // 'invoice' | 'prescription' | 'receipt' | 'purchase_order' | 'delivery_note' | 'certificate' | 'auto'
  language: 'en', // 'en' | 'vi'
});

console.log(result.documentType);
console.log(result.confidence);
console.log(JSON.parse(result.data)); // structured extracted data
```

#### Using local LLM (on-device, no API key needed)

```typescript
import { scanner, LocalLlmProvider, extractDocument } from 'react-native-pharma-scanner';

// Check if model is already downloaded
if (!scanner.isLocalLlmModelReady()) {
  await scanner.downloadLocalLlmModel((progress) => {
    console.log(`Download: ${(progress * 100).toFixed(1)}%`);
  });
}

const provider = new LocalLlmProvider();

const result = await extractDocument(provider, imageUri, {
  documentType: 'auto',
  language: 'en',
});

// Unload model when done to free memory
scanner.unloadLocalLlmModel();
```

### Custom document schemas

```typescript
import { registerSchema, extractDocument } from 'react-native-pharma-scanner';

// Register a custom schema
registerSchema({
  type: 'lab_report',
  displayName: 'Lab Report',
  fields: [
    { name: 'patientName', type: 'string', required: true },
    { name: 'testDate', type: 'string', required: true },
    { name: 'results', type: 'array', required: true },
  ],
});

// Use it for extraction
const result = await extractDocument(provider, imageUri, {
  documentType: 'lab_report',
});
```

### Validation

```typescript
import { validateDocumentData } from 'react-native-pharma-scanner';

const validation = validateDocumentData('invoice', extractedData);
if (validation.isValid) {
  console.log('All fields valid');
} else {
  validation.issues.forEach((issue) => {
    console.warn(`${issue.severity}: ${issue.message}`);
  });
}
```

## API Reference

### Native scanner methods

| Method | Description |
|--------|-------------|
| `ping()` | Health check, returns a string |
| `getVersion()` | Returns library version |
| `startCamera()` | Start the camera session |
| `stopCamera()` | Stop the camera session |
| `capturePhoto()` | Capture a photo, returns `CapturedImage` |
| `setFlash(mode)` | Set flash mode: `'auto'`, `'on'`, `'off'` |
| `setZoom(factor)` | Set camera zoom factor |
| `detectDocument(imageUri)` | Detect document edges in an image |
| `cropAndCorrect(imageUri, corners)` | Crop and perspective-correct a document |
| `scanDocument()` | Full document scan flow (detect + capture + correct) |
| `scanBarcodes(options)` | Scan barcodes from an image |
| `startContinuousScan(formats, callback)` | Start continuous barcode scanning |
| `stopContinuousScan()` | Stop continuous barcode scanning |
| `recognizeText(imageUri)` | Run OCR on an image |
| `extractDocument(imageUri, options)` | Extract structured data (native) |
| `isLocalLlmModelReady()` | Check if on-device LLM model is downloaded |
| `downloadLocalLlmModel(onProgress)` | Download the on-device LLM model |
| `unloadLocalLlmModel()` | Unload LLM model from memory |

### AI Providers

| Provider | Description |
|----------|-------------|
| `MistralProvider` | Mistral AI vision models |
| `OpenAIProvider` | OpenAI GPT-4 vision models |
| `ClaudeProvider` | Anthropic Claude vision models |
| `LocalLlmProvider` | On-device LLM via llama.cpp |

### Document types

Built-in: `invoice`, `prescription`, `receipt`, `purchase_order`, `delivery_note`, `certificate`, `auto`

Custom types can be registered via `registerSchema()`.

## License

MIT
