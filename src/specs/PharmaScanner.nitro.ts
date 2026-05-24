import type { HybridObject } from 'react-native-nitro-modules';
import type { FlashMode, CapturedImage, Corners, DocumentDetection, BarcodeScanOptions, BarcodeResult, BarcodeFormat } from './types.nitro';

export interface PharmaScanner
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  ping(): string;
  getVersion(): string;
  startCamera(): void;
  stopCamera(): void;
  capturePhoto(): Promise<CapturedImage>;
  setFlash(mode: FlashMode): void;
  setZoom(factor: number): void;
  detectDocument(imageUri: string): Promise<DocumentDetection>;
  cropAndCorrect(imageUri: string, corners: Corners): Promise<CapturedImage>;
  setOnDocumentDetected(callback: (detection: DocumentDetection) => void): void;
  scanDocument(): Promise<CapturedImage[]>;
  scanBarcodes(options: BarcodeScanOptions): Promise<BarcodeResult[]>;
  startContinuousScan(formats: BarcodeFormat[], onDetected: (codes: BarcodeResult[]) => void): void;
  stopContinuousScan(): void;
}
