import { NitroModules } from 'react-native-nitro-modules';
import type { PharmaScanner } from './specs/PharmaScanner.nitro';

export const scanner = NitroModules.createHybridObject<PharmaScanner>('PharmaScanner');

export { PharmaScannerCameraView } from './PharmaScannerCameraView';
export type { CapturedImage, FlashMode, Point, Corners, DocumentDetection, BarcodeFormat, BarcodeScanOptions, BarcodeResult, FrameRect, OcrResult, TextBlock, TextLine, TextElement } from './specs/types.nitro';
