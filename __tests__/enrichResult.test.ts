import { enrichExtractionResult } from '../src/utils/enrichResult';
import type { DocumentExtractionResult } from '../src/specs/types.nitro';

function makeResult(
  overrides: Partial<DocumentExtractionResult> = {},
): DocumentExtractionResult {
  return {
    documentType: 'invoice',
    data: '{}',
    rawText: 'raw ocr text',
    confidence: 0.9,
    extractionMethod: 'mistral',
    processingTimeMs: 1000,
    ocrTimeMs: 500,
    warnings: [],
    ...overrides,
  };
}

describe('enrichExtractionResult', () => {
  it('returns empty validationIssues for valid invoice data', () => {
    const future = new Date();
    future.setFullYear(future.getFullYear() + 2);
    const expiryDate = `01/01/${future.getFullYear()}`;

    const data = {
      seller: {
        companyName: 'Test',
        taxCode: '',
        address: '',
        phone: '',
        bankAccount: '',
      },
      buyer: { companyName: 'Test', taxCode: '', address: '' },
      metadata: { serial: '', number: '', date: '', form: '' },
      items: [
        {
          stt: 1,
          productName: 'Drug A',
          lotNumber: 'LOT-001',
          expiryDate,
          unit: 'box',
          quantity: 10,
          unitPrice: 100,
          amount: 1000,
        },
      ],
      totals: {
        subtotal: 1000,
        vatRate: 10,
        vatAmount: 100,
        totalPayment: 1100,
        amountInWords: '',
      },
    };

    const result = makeResult({ data: JSON.stringify(data) });
    const enriched = enrichExtractionResult(result);
    expect(enriched.validationIssues).toHaveLength(0);
    expect(enriched.warnings).toHaveLength(0);
  });

  it('appends validation warnings for expired items', () => {
    const data = {
      seller: {
        companyName: 'Test',
        taxCode: '',
        address: '',
        phone: '',
        bankAccount: '',
      },
      buyer: { companyName: 'Test', taxCode: '', address: '' },
      metadata: { serial: '', number: '', date: '', form: '' },
      items: [
        {
          stt: 1,
          productName: 'Drug A',
          lotNumber: 'LOT-001',
          expiryDate: '01/01/2020',
          unit: 'box',
          quantity: 10,
          unitPrice: 100,
          amount: 1000,
        },
      ],
      totals: {
        subtotal: 1000,
        vatRate: 10,
        vatAmount: 100,
        totalPayment: 1100,
        amountInWords: '',
      },
    };

    const result = makeResult({ data: JSON.stringify(data) });
    const enriched = enrichExtractionResult(result);
    expect(enriched.validationIssues.length).toBeGreaterThan(0);
    expect(enriched.validationIssues.some(i => i.code === 'EXPIRED')).toBe(
      true,
    );
    expect(
      enriched.warnings.some(w => w.startsWith('VALIDATION:ERROR:')),
    ).toBe(true);
  });

  it('returns result unchanged with empty validationIssues for unparseable data', () => {
    const result = makeResult({ data: 'not valid json' });
    const enriched = enrichExtractionResult(result);
    expect(enriched.validationIssues).toHaveLength(0);
    expect(enriched.warnings).toHaveLength(0);
  });

  it('returns result with no issues for empty data "{}"', () => {
    const result = makeResult({ data: '{}' });
    const enriched = enrichExtractionResult(result);
    expect(enriched.validationIssues).toHaveLength(0);
  });

  it('preserves all original fields', () => {
    const result = makeResult({
      documentType: 'receipt',
      confidence: 0.85,
      extractionMethod: 'local_llm',
      processingTimeMs: 2000,
      ocrTimeMs: 800,
      rawText: 'some raw text',
      warnings: ['existing warning'],
    });
    const enriched = enrichExtractionResult(result);
    expect(enriched.documentType).toBe('receipt');
    expect(enriched.confidence).toBe(0.85);
    expect(enriched.extractionMethod).toBe('local_llm');
    expect(enriched.processingTimeMs).toBe(2000);
    expect(enriched.ocrTimeMs).toBe(800);
    expect(enriched.rawText).toBe('some raw text');
    expect(enriched.warnings).toContain('existing warning');
  });

  it('appends all validation issues as formatted strings to warnings', () => {
    const data = {
      seller: {
        companyName: 'Test',
        taxCode: '',
        address: '',
        phone: '',
        bankAccount: '',
      },
      buyer: { companyName: 'Test', taxCode: '', address: '' },
      metadata: { serial: '', number: '', date: '', form: '' },
      items: [
        {
          stt: 1,
          productName: 'Drug A',
          lotNumber: '0000',
          expiryDate: '01/01/2020',
          unit: 'box',
          quantity: 10,
          unitPrice: 100,
          amount: 1000,
        },
      ],
      totals: {
        subtotal: 1000,
        vatRate: 10,
        vatAmount: 100,
        totalPayment: 1100,
        amountInWords: '',
      },
    };

    const result = makeResult({
      data: JSON.stringify(data),
      warnings: ['pre-existing'],
    });
    const enriched = enrichExtractionResult(result);
    // Should have multiple validation issues (expired + suspicious lot)
    expect(enriched.validationIssues.length).toBeGreaterThanOrEqual(2);
    // All validation issues should be in warnings array
    expect(enriched.warnings.length).toBe(
      1 + enriched.validationIssues.length,
    );
    expect(enriched.warnings[0]).toBe('pre-existing');
    enriched.warnings.slice(1).forEach(w => {
      expect(w).toMatch(/^VALIDATION:(ERROR|WARNING|INFO):/);
    });
  });
});
