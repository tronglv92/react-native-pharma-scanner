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

export interface InvoiceSeller {
  companyName: string;
  taxCode: string;
  address: string;
  phone: string;
  bankAccount: string;
}

export interface InvoiceBuyer {
  companyName: string;
  taxCode: string;
  address: string;
}

export interface InvoiceMetadata {
  serial: string;
  number: string;
  date: string;
  form: string;
}

export interface InvoiceLineItem {
  stt: number;
  productName: string;
  lotNumber: string;
  expiryDate: string;
  unit: string;
  quantity: number;
  unitPrice: number;
  amount: number;
}

export interface InvoiceTotals {
  subtotal: number;
  vatRate: number;
  vatAmount: number;
  totalPayment: number;
  amountInWords: string;
}

export interface InvoiceResult {
  seller: InvoiceSeller;
  buyer: InvoiceBuyer;
  metadata: InvoiceMetadata;
  items: InvoiceLineItem[];
  totals: InvoiceTotals;
  rawText: string;
  confidence: number;
  processingTimeMs: number;
  warnings: string[];
}

export interface StructuredParagraph {
  text: string;
  position: string;         // "top" | "middle" | "bottom"
  boundingBox: FrameRect;
}

export interface TableRow {
  cells: string[];
}

export interface StructuredTable {
  rows: TableRow[];
  boundingBox: FrameRect;
}

export interface DetectedEntity {
  type: string;              // "date"|"money"|"phone"|"email"|"url"|"address"
  value: string;
  context: string;           // surrounding text
}

export interface KeyValuePair {
  key: string;
  value: string;
}

export interface DocumentSummary {
  keyValuePairs: KeyValuePair[];
  moneyAmounts: string[];
  dates: string[];
  identifiers: string[];     // tax codes, phone numbers, IDs
}

export interface StructuredDocumentResult {
  documentType: string;
  paragraphs: StructuredParagraph[];
  tables: StructuredTable[];
  detectedEntities: DetectedEntity[];
  barcodes: string[];
  summary: DocumentSummary;
  rawText: string;
  confidence: number;
  processingTimeMs: number;
}

export interface ExtractionOptions {
  documentType: string;      // "invoice"|"prescription"|"receipt"|"purchase_order"|"delivery_note"|"certificate"|"auto"
  language: string;          // "vi"|"en"
  customPrompt?: string;     // Optional: user-provided extraction instructions
  forceOffline?: boolean;    // Optional: force template extraction
  scanOcr?: boolean;         // Optional: use RecognizeDocumentsRequest (iOS 26+) for on-device structured OCR
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
