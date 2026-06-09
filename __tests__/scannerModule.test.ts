import {
  scanner,
  DOCUMENT_TYPES,
  parseDocumentData,
  validateDocumentData,
  enrichExtractionResult,
  ScanError,
  mapToScanError,
  withErrorMapping,
} from '../src';

describe('scanner module (mocked)', () => {
  it('scanner object has expected methods', () => {
    expect(typeof scanner.ping).toBe('function');
    expect(typeof scanner.getVersion).toBe('function');
    expect(typeof scanner.startCamera).toBe('function');
    expect(typeof scanner.stopCamera).toBe('function');
    expect(typeof scanner.capturePhoto).toBe('function');
    expect(typeof scanner.setFlash).toBe('function');
    expect(typeof scanner.setZoom).toBe('function');
    expect(typeof scanner.detectDocument).toBe('function');
    expect(typeof scanner.cropAndCorrect).toBe('function');
    expect(typeof scanner.scanDocument).toBe('function');
    expect(typeof scanner.scanBarcodes).toBe('function');
    expect(typeof scanner.startContinuousScan).toBe('function');
    expect(typeof scanner.stopContinuousScan).toBe('function');
    expect(typeof scanner.recognizeText).toBe('function');
    expect(typeof scanner.extractDocument).toBe('function');
    expect(typeof scanner.isLocalLlmModelReady).toBe('function');
    expect(typeof scanner.downloadLocalLlmModel).toBe('function');
    expect(typeof scanner.unloadLocalLlmModel).toBe('function');
  });

  it('scanner.ping() returns "pong" from mock', () => {
    expect(scanner.ping()).toBe('pong');
  });

  it('scanner.getVersion() returns expected string from mock', () => {
    expect(scanner.getVersion()).toBe('1.0.0-test');
  });
});

describe('public API exports', () => {
  it('DOCUMENT_TYPES is an array of correct length', () => {
    expect(Array.isArray(DOCUMENT_TYPES)).toBe(true);
    expect(DOCUMENT_TYPES).toHaveLength(7);
  });

  it('parseDocumentData is callable', () => {
    expect(typeof parseDocumentData).toBe('function');
    const result = parseDocumentData('{"test": 1}');
    expect(result).toEqual({ test: 1 });
  });

  it('validateDocumentData is callable', () => {
    expect(typeof validateDocumentData).toBe('function');
    const result = validateDocumentData('unknown', {});
    expect(result).toHaveProperty('issues');
    expect(result).toHaveProperty('isValid');
  });

  it('enrichExtractionResult is callable', () => {
    expect(typeof enrichExtractionResult).toBe('function');
  });

  it('ScanError is importable and constructible', () => {
    const err = new ScanError('UNKNOWN', 'test error');
    expect(err).toBeInstanceOf(Error);
    expect(err).toBeInstanceOf(ScanError);
    expect(err.code).toBe('UNKNOWN');
  });

  it('mapToScanError is callable', () => {
    expect(typeof mapToScanError).toBe('function');
    const err = mapToScanError(new Error('test'));
    expect(err).toBeInstanceOf(ScanError);
  });

  it('withErrorMapping is callable', () => {
    expect(typeof withErrorMapping).toBe('function');
  });
});
