import { NitroModules } from 'react-native-nitro-modules';
import type { PharmaScanner } from './specs/PharmaScanner.nitro';

export const scanner = NitroModules.createHybridObject<PharmaScanner>('PharmaScanner');

export { PharmaScannerCameraView } from './PharmaScannerCameraView';
export type { CapturedImage, FlashMode, Point, Corners, DocumentDetection, BarcodeFormat, BarcodeScanOptions, BarcodeResult, FrameRect, OcrResult, TextBlock, TextLine, TextElement, InvoiceResult, InvoiceSeller, InvoiceBuyer, InvoiceMetadata, InvoiceLineItem, InvoiceTotals, ExtractionOptions, DocumentExtractionResult, StructuredDocumentResult, StructuredParagraph, StructuredTable, TableRow, DetectedEntity, KeyValuePair, DocumentSummary } from './specs/types.nitro';
export { organizeDocument } from './structured-document';
export type { OrganizedDocument } from './structured-document';
export { DOCUMENT_TYPES, parseDocumentData } from './document-types';
export type { InvoiceData, PrescriptionData, ReceiptData, PurchaseOrderData, DeliveryNoteData, CertificateData, DocumentTypeInfo } from './document-types';
export { extractWithTemplate } from './template-engine';
export type { DocumentTemplate, TemplateResult } from './template-engine';
export { registerTemplate, registerTemplateObject, unregisterTemplate, getCustomTemplates, getAllTemplates } from './templates';
