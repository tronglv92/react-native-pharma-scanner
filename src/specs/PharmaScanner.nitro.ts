import type { HybridObject } from 'react-native-nitro-modules';
import type { FlashMode, CapturedImage, Corners, DocumentDetection, BarcodeScanOptions, BarcodeResult, BarcodeFormat, OcrResult, ExtractionOptions, DocumentExtractionResult } from './types.nitro';

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
  recognizeText(imageUri: string): Promise<OcrResult>;
  recognizeDocument(imageUri: string): Promise<OcrResult>;
  setOnTextRecognized(callback: (result: OcrResult) => void): void;
  configure(apiKey: string, baseUrl: string): void;
  extractDocument(imageUri: string, options: ExtractionOptions): Promise<DocumentExtractionResult>;

  // Local LLM (Qwen3-1.7B via llama.cpp)
  isLocalLlmModelReady(): boolean;
  downloadLocalLlmModel(onProgress: (progress: number) => void): Promise<void>;
  unloadLocalLlmModel(): void;
}
