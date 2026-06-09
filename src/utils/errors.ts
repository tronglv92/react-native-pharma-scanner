export type ScanErrorCode =
  | 'CAMERA_PERMISSION_DENIED'
  | 'CAMERA_NOT_AVAILABLE'
  | 'OCR_FAILED'
  | 'NO_DOCUMENT_DETECTED'
  | 'IMAGE_TOO_BLURRY'
  | 'PROCESSING_CANCELLED'
  | 'MODEL_NOT_READY'
  | 'EXTRACTION_FAILED'
  | 'NETWORK_ERROR'
  | 'UNKNOWN';

export class ScanError extends Error {
  code: ScanErrorCode;
  originalError?: Error;

  constructor(code: ScanErrorCode, message: string, originalError?: Error) {
    super(message);
    this.name = 'ScanError';
    this.code = code;
    this.originalError = originalError;
  }
}

const ERROR_PATTERNS: Array<[RegExp, ScanErrorCode]> = [
  [/permission denied|not authorized/i, 'CAMERA_PERMISSION_DENIED'],
  [/camera.*not available|session.*not running/i, 'CAMERA_NOT_AVAILABLE'],
  [/no document|could not detect/i, 'NO_DOCUMENT_DETECTED'],
  [/too blurry/i, 'IMAGE_TOO_BLURRY'],
  [/model not downloaded/i, 'MODEL_NOT_READY'],
  [/cancel|abort|stopped/i, 'PROCESSING_CANCELLED'],
  [/network|fetch|timeout|Mistral.*error/i, 'NETWORK_ERROR'],
  [/no text recognized|OCR/i, 'OCR_FAILED'],
];

export function mapToScanError(error: unknown): ScanError {
  if (error instanceof ScanError) {
    return error;
  }

  const message =
    error instanceof Error ? error.message : String(error ?? 'Unknown error');
  const originalError = error instanceof Error ? error : undefined;

  for (const [pattern, code] of ERROR_PATTERNS) {
    if (pattern.test(message)) {
      return new ScanError(code, message, originalError);
    }
  }

  return new ScanError('UNKNOWN', message, originalError);
}

export function withErrorMapping<T>(promise: Promise<T>): Promise<T> {
  return promise.catch(error => {
    throw mapToScanError(error);
  });
}
