import type { HybridObject } from 'react-native-nitro-modules';
import type { FlashMode, CapturedImage } from './types.nitro';

export interface PharmaScanner
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  ping(): string;
  getVersion(): string;
  startCamera(): void;
  stopCamera(): void;
  capturePhoto(): Promise<CapturedImage>;
  setFlash(mode: FlashMode): void;
  setZoom(factor: number): void;
}
