import { NitroModules } from 'react-native-nitro-modules';
import type { PharmaScanner } from './specs/PharmaScanner.nitro';

export const scanner = NitroModules.createHybridObject<PharmaScanner>('PharmaScanner');

export { PharmaScannerCameraView } from './PharmaScannerCameraView';
export type { CapturedImage, FlashMode, Point, Corners, DocumentDetection, BarcodeFormat, BarcodeScanOptions, BarcodeResult, FrameRect, OcrResult, TextBlock, TextLine, TextElement, ExtractionOptions, DocumentExtractionResult } from './specs/types.nitro';
export { DOCUMENT_TYPES, parseDocumentData } from './document-types';
export type { InvoiceData, PrescriptionData, ReceiptData, PurchaseOrderData, DeliveryNoteData, CertificateData, DocumentTypeInfo } from './document-types';
export { validateDocumentData } from './utils/validation';
export type { ValidationIssue, ValidationResult, ValidationSeverity } from './utils/validation';
export { enrichExtractionResult } from './utils/enrichResult';
export { ScanError, mapToScanError, withErrorMapping } from './utils/errors';
export type { ScanErrorCode } from './utils/errors';
