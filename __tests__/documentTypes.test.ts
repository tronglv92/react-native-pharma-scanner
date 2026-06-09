import { DOCUMENT_TYPES, parseDocumentData } from '../src/document-types';

describe('parseDocumentData', () => {
  it('parses valid JSON and returns object', () => {
    const result = parseDocumentData('{"name": "test", "value": 42}');
    expect(result).toEqual({ name: 'test', value: 42 });
  });

  it('returns null for invalid JSON', () => {
    const result = parseDocumentData('not json at all {{{');
    expect(result).toBeNull();
  });

  it('returns null for empty string', () => {
    const result = parseDocumentData('');
    expect(result).toBeNull();
  });

  it('parses JSON array', () => {
    const result = parseDocumentData('[1, 2, 3]');
    expect(result).toEqual([1, 2, 3]);
  });

  it('supports generic type parameter', () => {
    interface TestData {
      name: string;
    }
    const result = parseDocumentData<TestData>('{"name": "typed"}');
    expect(result?.name).toBe('typed');
  });
});

describe('DOCUMENT_TYPES', () => {
  it('has 7 entries', () => {
    expect(DOCUMENT_TYPES).toHaveLength(7);
  });

  it('contains expected keys', () => {
    const keys = DOCUMENT_TYPES.map(dt => dt.key);
    expect(keys).toEqual([
      'auto',
      'invoice',
      'prescription',
      'receipt',
      'purchase_order',
      'delivery_note',
      'certificate',
    ]);
  });

  it('each entry has key, label, and description', () => {
    for (const dt of DOCUMENT_TYPES) {
      expect(typeof dt.key).toBe('string');
      expect(dt.key.length).toBeGreaterThan(0);
      expect(typeof dt.label).toBe('string');
      expect(dt.label.length).toBeGreaterThan(0);
      expect(typeof dt.description).toBe('string');
      expect(dt.description.length).toBeGreaterThan(0);
    }
  });
});
