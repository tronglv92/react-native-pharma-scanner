export type FlashMode = 'auto' | 'on' | 'off';

export interface CapturedImage {
  uri: string;
  width: number;
  height: number;
  base64?: string;
}

export interface Point {
  x: number;
  y: number;
}

export interface Corners {
  topLeft: Point;
  topRight: Point;
  bottomLeft: Point;
  bottomRight: Point;
}

export interface DocumentDetection {
  detected: boolean;
  corners: Corners;
  confidence: number;
  isStable: boolean;
}

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

export interface TextElement {
  text: string;
  boundingBox: FrameRect;
}

export interface TextLine {
  text: string;
  boundingBox: FrameRect;
  confidence: number;
  elements: TextElement[];
}

export interface TextBlock {
  text: string;
  boundingBox: FrameRect;
  lines: TextLine[];
}

export interface OcrResult {
  text: string;
  blocks: TextBlock[];
  processingTimeMs: number;
}

export interface ExtractionOptions {
  documentType: string;      // "invoice"|"prescription"|"receipt"|"purchase_order"|"delivery_note"|"certificate"|"auto"
  language: string;          // "vi"|"en"
  customPrompt?: string;     // Optional: user-provided extraction instructions
  forceOffline?: boolean;    // Optional: force template extraction
}

export interface DocumentExtractionResult {
  documentType: string;      // Detected/confirmed document type
  data: string;              // JSON string with extracted fields (flexible schema)
  rawText: string;           // Original OCR text
  confidence: number;        // 0-1
  extractionMethod: string;  // "llm"|"template"
  processingTimeMs: number;  // Total time (OCR + extraction)
  ocrTimeMs: number;         // OCR-only time
  warnings: string[];
}
