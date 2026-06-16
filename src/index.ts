import { NitroModules } from 'react-native-nitro-modules';
import type { PharmaScanner } from './specs/PharmaScanner.nitro';

export const scanner = NitroModules.createHybridObject<PharmaScanner>('PharmaScanner');

// --- Existing exports (preserved for backward compatibility) ---
export { PharmaScannerCameraView } from './PharmaScannerCameraView';
export type { CapturedImage, FlashMode, Point, Corners, DocumentDetection, BarcodeFormat, BarcodeScanOptions, BarcodeResult, FrameRect, OcrResult, TextBlock, TextLine, TextElement, ExtractionOptions, DocumentExtractionResult } from './specs/types.nitro';
export { DOCUMENT_TYPES, parseDocumentData } from './document-types';
export type { InvoiceData, PrescriptionData, ReceiptData, PurchaseOrderData, DeliveryNoteData, CertificateData, DocumentTypeInfo } from './document-types';
export { validateDocumentData } from './utils/validation';
export type { ValidationIssue, ValidationResult, ValidationSeverity } from './utils/validation';
export { enrichExtractionResult } from './utils/enrichResult';
export { ScanError, mapToScanError, withErrorMapping } from './utils/errors';
export type { ScanErrorCode } from './utils/errors';

// --- Extraction orchestrator ---
export { extractDocument } from './extract';
export type { ExtractDocumentOptions } from './extract';

// --- AI provider system ---
export type { AIProvider, AIProviderConfig, ExtractionInput, ExtractionOutput } from './providers';
export { MistralProvider } from './providers';
export { OpenAIProvider } from './providers';
export { ClaudeProvider } from './providers';
export { LocalLlmProvider } from './providers';

// --- Schema system ---
export type { DocumentSchema } from './schemas';
export { registerSchema, registerSchemas, getSchema, getAllSchemas, unregisterSchema, schemaToPrompt, generateAutoDetectPrompt } from './schemas';

// --- Shared utilities ---
export { extractJSON } from './utils/json';
export { computeConfidence } from './utils/confidence';
export { fileToBase64, getMimeType } from './utils/image';
