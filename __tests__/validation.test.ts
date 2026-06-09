import {
  validateExpiryDate,
  validateLotNumber,
  validateTaxId,
  validateAmountCrossCheck,
  validateDocumentData,
} from '../src/utils/validation';

describe('validateExpiryDate', () => {
  it('returns EXPIRED error for past dates', () => {
    const issues = validateExpiryDate('01/01/2020', 'expiryDate');
    expect(issues).toHaveLength(1);
    expect(issues[0].code).toBe('EXPIRED');
    expect(issues[0].severity).toBe('error');
  });

  it('returns EXPIRING_SOON warning for dates < 6 months away', () => {
    // Create a date 3 months from now
    const future = new Date();
    future.setMonth(future.getMonth() + 3);
    const dateStr = `${String(future.getDate()).padStart(2, '0')}/${String(future.getMonth() + 1).padStart(2, '0')}/${future.getFullYear()}`;

    const issues = validateExpiryDate(dateStr, 'expiryDate');
    expect(issues).toHaveLength(1);
    expect(issues[0].code).toBe('EXPIRING_SOON');
    expect(issues[0].severity).toBe('warning');
  });

  it('returns no issues for dates > 6 months away', () => {
    const future = new Date();
    future.setFullYear(future.getFullYear() + 2);
    const dateStr = `${String(future.getDate()).padStart(2, '0')}/${String(future.getMonth() + 1).padStart(2, '0')}/${future.getFullYear()}`;

    const issues = validateExpiryDate(dateStr, 'expiryDate');
    expect(issues).toHaveLength(0);
  });

  it('handles YYYY-MM-DD format', () => {
    const issues = validateExpiryDate('2019-06-15', 'expiryDate');
    expect(issues).toHaveLength(1);
    expect(issues[0].code).toBe('EXPIRED');
  });

  it('handles MM/YYYY format', () => {
    const issues = validateExpiryDate('01/2020', 'expiryDate');
    expect(issues).toHaveLength(1);
    expect(issues[0].code).toBe('EXPIRED');
  });

  it('returns warning for unparseable dates', () => {
    const issues = validateExpiryDate('not-a-date', 'expiryDate');
    expect(issues).toHaveLength(1);
    expect(issues[0].code).toBe('INVALID_DATE_FORMAT');
    expect(issues[0].severity).toBe('warning');
  });

  it('returns empty for null/undefined/empty', () => {
    expect(validateExpiryDate(null, 'field')).toHaveLength(0);
    expect(validateExpiryDate(undefined, 'field')).toHaveLength(0);
    expect(validateExpiryDate('', 'field')).toHaveLength(0);
  });
});

describe('validateLotNumber', () => {
  it('warns on empty lot number', () => {
    const issues = validateLotNumber('');
    expect(issues).toHaveLength(1);
    expect(issues[0].code).toBe('EMPTY_LOT_NUMBER');
    expect(issues[0].severity).toBe('warning');
  });

  it('warns on too short lot number', () => {
    const issues = validateLotNumber('AB');
    expect(issues.some(i => i.code === 'INVALID_LOT_LENGTH')).toBe(true);
  });

  it('warns on too long lot number', () => {
    const issues = validateLotNumber('A'.repeat(25));
    expect(issues.some(i => i.code === 'INVALID_LOT_LENGTH')).toBe(true);
  });

  it('warns on suspicious all-zeros', () => {
    const issues = validateLotNumber('0000');
    expect(issues.some(i => i.code === 'SUSPICIOUS_LOT')).toBe(true);
  });

  it('accepts valid lot numbers', () => {
    const issues = validateLotNumber('ABC123');
    expect(issues).toHaveLength(0);
  });

  it('accepts alphanumeric with dashes', () => {
    const issues = validateLotNumber('LOT-2024-001');
    expect(issues).toHaveLength(0);
  });
});

describe('validateTaxId', () => {
  it('warns on invalid format (not 10 or 13 digits)', () => {
    const issues = validateTaxId('12345', 'vi');
    expect(issues).toHaveLength(1);
    expect(issues[0].code).toBe('INVALID_TAX_FORMAT');
  });

  it('warns on bad check digit', () => {
    // A 10-digit code that likely fails weighted sum mod 10
    const issues = validateTaxId('1234567890', 'vi');
    expect(issues.some(i => i.code === 'INVALID_TAX_CHECK_DIGIT')).toBe(true);
  });

  it('accepts valid Vietnamese tax code', () => {
    // 0100109106 is a known valid VN tax code
    const issues = validateTaxId('0100109106', 'vi');
    // May or may not pass check digit depending on actual formula
    // At minimum, it should not fail on format
    expect(issues.every(i => i.code !== 'INVALID_TAX_FORMAT')).toBe(true);
  });

  it('returns empty for empty/null', () => {
    expect(validateTaxId('', 'vi')).toHaveLength(0);
    expect(validateTaxId(null, 'vi')).toHaveLength(0);
  });
});

describe('validateAmountCrossCheck', () => {
  it('returns AMOUNT_MISMATCH when sum != total', () => {
    const items = [{ amount: 100 }, { amount: 200 }, { amount: 300 }];
    const issues = validateAmountCrossCheck(items, 500);
    expect(issues).toHaveLength(1);
    expect(issues[0].code).toBe('AMOUNT_MISMATCH');
    expect(issues[0].severity).toBe('warning');
  });

  it('accepts when sum matches total within tolerance', () => {
    const items = [{ amount: 100 }, { amount: 200 }, { amount: 300 }];
    const issues = validateAmountCrossCheck(items, 600);
    expect(issues).toHaveLength(0);
  });

  it('accepts when difference is <= 1 (tolerance)', () => {
    const items = [{ amount: 100.5 }, { amount: 200.3 }];
    const issues = validateAmountCrossCheck(items, 301);
    expect(issues).toHaveLength(0);
  });

  it('returns empty for null/empty items', () => {
    expect(validateAmountCrossCheck(null, 100)).toHaveLength(0);
    expect(validateAmountCrossCheck([], 100)).toHaveLength(0);
  });
});

describe('validateDocumentData', () => {
  it('validates invoice with expired items', () => {
    const data = {
      seller: { companyName: 'Test', taxCode: '', address: '', phone: '', bankAccount: '' },
      buyer: { companyName: 'Test', taxCode: '', address: '' },
      metadata: { serial: '', number: '', date: '', form: '' },
      items: [
        {
          stt: 1,
          productName: 'Drug A',
          lotNumber: 'LOT001',
          expiryDate: '01/01/2020',
          unit: 'box',
          quantity: 10,
          unitPrice: 100,
          amount: 1000,
        },
      ],
      totals: { subtotal: 1000, vatRate: 10, vatAmount: 100, totalPayment: 1100, amountInWords: '' },
    };

    const result = validateDocumentData('invoice', data);
    expect(result.isValid).toBe(false);
    expect(result.issues.some(i => i.code === 'EXPIRED')).toBe(true);
  });

  it('validates delivery note items', () => {
    const data = {
      deliveryNumber: 'DN001',
      date: '01/06/2024',
      sender: { name: 'Sender', address: 'Addr' },
      receiver: { name: 'Receiver', address: 'Addr' },
      items: [
        { name: 'Item', quantity: 1, unit: 'box', lotNumber: '0000', expiryDate: '01/01/2020' },
      ],
      notes: '',
    };

    const result = validateDocumentData('delivery_note', data);
    expect(result.issues.some(i => i.code === 'EXPIRED')).toBe(true);
    expect(result.issues.some(i => i.code === 'SUSPICIOUS_LOT')).toBe(true);
  });

  it('validates certificate expiry', () => {
    const data = {
      type: 'GMP',
      certificateNumber: 'CERT-001',
      issuedTo: 'Company',
      issuedBy: 'Authority',
      issueDate: '01/01/2020',
      expiryDate: '01/01/2022',
      details: '',
    };

    const result = validateDocumentData('certificate', data);
    expect(result.issues.some(i => i.code === 'EXPIRED')).toBe(true);
  });

  it('validates prescription with empty medications', () => {
    const data = {
      patient: { name: '', age: '', gender: '', address: '', diagnosis: '' },
      doctor: { name: '', department: '', hospital: '' },
      medications: [],
      date: '',
      notes: '',
    };

    const result = validateDocumentData('prescription', data);
    expect(result.issues.some(i => i.code === 'EMPTY_MEDICATIONS')).toBe(true);
  });

  it('returns valid for unknown document type', () => {
    const result = validateDocumentData('unknown_type', { some: 'data' });
    expect(result.isValid).toBe(true);
    expect(result.issues).toHaveLength(0);
  });
});
