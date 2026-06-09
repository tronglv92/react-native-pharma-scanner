import {
  ScanError,
  mapToScanError,
  withErrorMapping,
} from '../src/utils/errors';

describe('ScanError', () => {
  it('creates error with code and message', () => {
    const err = new ScanError('OCR_FAILED', 'No text recognized');
    expect(err.code).toBe('OCR_FAILED');
    expect(err.message).toBe('No text recognized');
    expect(err.name).toBe('ScanError');
    expect(err instanceof Error).toBe(true);
  });

  it('preserves original error', () => {
    const original = new Error('original');
    const err = new ScanError('UNKNOWN', 'wrapped', original);
    expect(err.originalError).toBe(original);
  });
});

describe('mapToScanError', () => {
  it('maps "permission denied" to CAMERA_PERMISSION_DENIED', () => {
    const err = mapToScanError(new Error('Camera permission denied by user'));
    expect(err.code).toBe('CAMERA_PERMISSION_DENIED');
  });

  it('maps "not authorized" to CAMERA_PERMISSION_DENIED', () => {
    const err = mapToScanError(new Error('Not authorized to access camera'));
    expect(err.code).toBe('CAMERA_PERMISSION_DENIED');
  });

  it('maps "camera not available" to CAMERA_NOT_AVAILABLE', () => {
    const err = mapToScanError(new Error('Camera is not available'));
    expect(err.code).toBe('CAMERA_NOT_AVAILABLE');
  });

  it('maps "session not running" to CAMERA_NOT_AVAILABLE', () => {
    const err = mapToScanError(new Error('Camera session not running'));
    expect(err.code).toBe('CAMERA_NOT_AVAILABLE');
  });

  it('maps "no text recognized" to OCR_FAILED', () => {
    const err = mapToScanError(new Error('No text recognized in the image'));
    expect(err.code).toBe('OCR_FAILED');
  });

  it('maps "OCR processing failed" to OCR_FAILED', () => {
    const err = mapToScanError(new Error('OCR processing failed'));
    expect(err.code).toBe('OCR_FAILED');
  });

  it('maps "no document detected" to NO_DOCUMENT_DETECTED', () => {
    const err = mapToScanError(new Error('No document found in image'));
    expect(err.code).toBe('NO_DOCUMENT_DETECTED');
  });

  it('maps "could not detect" to NO_DOCUMENT_DETECTED', () => {
    const err = mapToScanError(new Error('Could not detect document'));
    expect(err.code).toBe('NO_DOCUMENT_DETECTED');
  });

  it('maps "too blurry" to IMAGE_TOO_BLURRY', () => {
    const err = mapToScanError(new Error('Image is too blurry to process'));
    expect(err.code).toBe('IMAGE_TOO_BLURRY');
  });

  it('maps "model not downloaded" to MODEL_NOT_READY', () => {
    const err = mapToScanError(
      new Error('Local LLM model not downloaded. Please download the model first.'),
    );
    expect(err.code).toBe('MODEL_NOT_READY');
  });

  it('maps "cancelled" to PROCESSING_CANCELLED', () => {
    const err = mapToScanError(new Error('Operation was cancelled'));
    expect(err.code).toBe('PROCESSING_CANCELLED');
  });

  it('maps "abort" to PROCESSING_CANCELLED', () => {
    const err = mapToScanError(new Error('The user aborted the request'));
    expect(err.code).toBe('PROCESSING_CANCELLED');
  });

  it('maps "network error" to NETWORK_ERROR', () => {
    const err = mapToScanError(new Error('Network request failed'));
    expect(err.code).toBe('NETWORK_ERROR');
  });

  it('maps "fetch failed" to NETWORK_ERROR', () => {
    const err = mapToScanError(new Error('fetch failed: connection timeout'));
    expect(err.code).toBe('NETWORK_ERROR');
  });

  it('maps "Mistral OCR error" to NETWORK_ERROR', () => {
    const err = mapToScanError(new Error('Mistral OCR error 500: Internal Server Error'));
    expect(err.code).toBe('NETWORK_ERROR');
  });

  it('maps "timeout" to NETWORK_ERROR', () => {
    const err = mapToScanError(new Error('Request timeout after 30s'));
    expect(err.code).toBe('NETWORK_ERROR');
  });

  it('maps unknown errors to UNKNOWN', () => {
    const err = mapToScanError(new Error('Something totally unexpected'));
    expect(err.code).toBe('UNKNOWN');
  });

  it('handles string errors', () => {
    const err = mapToScanError('permission denied');
    expect(err.code).toBe('CAMERA_PERMISSION_DENIED');
  });

  it('handles null/undefined', () => {
    const err = mapToScanError(null);
    expect(err.code).toBe('UNKNOWN');
    expect(err.message).toBe('Unknown error');
  });

  it('passes through existing ScanError', () => {
    const original = new ScanError('IMAGE_TOO_BLURRY', 'test');
    const mapped = mapToScanError(original);
    expect(mapped).toBe(original);
  });
});

describe('withErrorMapping', () => {
  it('passes through resolved values', async () => {
    const result = await withErrorMapping(Promise.resolve(42));
    expect(result).toBe(42);
  });

  it('maps rejected errors to ScanError', async () => {
    await expect(
      withErrorMapping(Promise.reject(new Error('Network request failed'))),
    ).rejects.toMatchObject({
      code: 'NETWORK_ERROR',
    });
  });

  it('wraps generic errors as UNKNOWN', async () => {
    await expect(
      withErrorMapping(Promise.reject(new Error('random failure'))),
    ).rejects.toMatchObject({
      code: 'UNKNOWN',
    });
  });
});
