import { extractJSON, computeMistralConfidence } from '../src/mistral';

describe('extractJSON', () => {
  it('returns direct JSON string as-is', () => {
    const input = '{"name": "test"}';
    expect(extractJSON(input)).toBe(input);
  });

  it('returns direct JSON array as-is', () => {
    const input = '[{"name": "test"}]';
    expect(extractJSON(input)).toBe(input);
  });

  it('extracts content from ```json code block', () => {
    const input = '```json\n{"name": "test"}\n```';
    expect(extractJSON(input)).toBe('{"name": "test"}');
  });

  it('extracts content from generic ``` code block', () => {
    const input = '```\n{"name": "test"}\n```';
    expect(extractJSON(input)).toBe('{"name": "test"}');
  });

  it('extracts embedded JSON from first { to last }', () => {
    const input = 'Here is the result: {"name": "test"} and some trailing text';
    expect(extractJSON(input)).toBe('{"name": "test"}');
  });

  it('returns trimmed input when no JSON found', () => {
    const input = '  no json here  ';
    expect(extractJSON(input)).toBe('no json here');
  });

  it('handles multiline JSON in code block', () => {
    const input = '```json\n{\n  "seller": "ABC",\n  "amount": 100\n}\n```';
    const result = extractJSON(input);
    const parsed = JSON.parse(result);
    expect(parsed.seller).toBe('ABC');
    expect(parsed.amount).toBe(100);
  });
});

describe('computeMistralConfidence', () => {
  it('returns ~0.95 for valid JSON with all fields filled', () => {
    const json = JSON.stringify({
      seller: 'Company A',
      buyer: 'Company B',
      date: '01/01/2024',
      items: [{ name: 'Item 1' }],
      total: 1000,
    });
    const confidence = computeMistralConfidence(json);
    expect(confidence).toBeCloseTo(0.95, 1);
  });

  it('returns ~0.82 for valid JSON with half fields empty', () => {
    const json = JSON.stringify({
      seller: 'Company A',
      buyer: '',
      date: '01/01/2024',
      items: [],
      total: 0,
      notes: '',
    });
    // 2 filled out of 6 fields => fillRatio = 2/6 ≈ 0.333
    // confidence = 0.7 + 0.333 * 0.25 ≈ 0.783
    const confidence = computeMistralConfidence(json);
    expect(confidence).toBeGreaterThanOrEqual(0.75);
    expect(confidence).toBeLessThanOrEqual(0.85);
  });

  it('returns 0.70 for valid JSON with all fields empty', () => {
    const json = JSON.stringify({
      seller: '',
      buyer: '',
      date: '',
      total: 0,
    });
    const confidence = computeMistralConfidence(json);
    expect(confidence).toBe(0.7);
  });

  it('returns 0.4 for invalid JSON', () => {
    const confidence = computeMistralConfidence('not valid json {{{');
    expect(confidence).toBe(0.4);
  });

  it('returns 0.5 for empty object {}', () => {
    const confidence = computeMistralConfidence('{}');
    expect(confidence).toBe(0.5);
  });

  it('returns 0.5 for non-object parsed value', () => {
    const confidence = computeMistralConfidence('"just a string"');
    expect(confidence).toBe(0.5);
  });

  it('caps at 0.95 even with many filled fields', () => {
    const obj: Record<string, string> = {};
    for (let i = 0; i < 50; i++) {
      obj[`field${i}`] = `value${i}`;
    }
    const confidence = computeMistralConfidence(JSON.stringify(obj));
    expect(confidence).toBe(0.95);
  });
});
