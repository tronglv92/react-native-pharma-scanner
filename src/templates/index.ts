import type { DocumentTemplate } from '../template-engine/types';

// ─── Invoice template ───────────────────────────────────────────────
const invoiceTemplate: DocumentTemplate = {
  name: 'invoice',
  version: 2,
  detection: {
    keywords: [
      'hoa don', 'invoice', 'mst', 'ma so thue', 'gtgt', 'vat',
      'gia tri gia tang', 'tax code', 'tax id', 'invoice no',
      'date of issue', 'seller', 'client', 'net price', 'net worth',
      'gross worth', 'items', 'summary',
    ],
  },
  sections: {
    invoice_meta: {
      flatten: true,
      startAt: 'document_start',
      endBefore: ['seller'],
      fields: {
        invoice_no: {
          type: 'string',
          default: '',
          strategies: [
            {
              method: 'keyword_label',
              keywords: ['invoice no', 'no.', 'no.f', 'so:', 'so (no'],
              extract: 'regex',
              pattern: '(\\d{4,})',
              checkNextLine: true,
              scope: 'full_text',
            },
          ],
        },
        date_of_issue: {
          type: 'string',
          default: '',
          strategies: [
            { method: 'us_date', scope: 'full_text' },
            { method: 'vietnamese_date', scope: 'full_text' },
            { method: 'regex', pattern: '(\\d{1,2}/\\d{1,2}/\\d{4})', scope: 'full_text' },
          ],
        },
      },
    },
    seller: {
      startKeywords: ['seller', 'cong ty', 'cty'],
      endBefore: ['buyer', 'client'],
      fields: {
        name: {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['seller'], extract: 'value_after_colon' },
            { method: 'keyword_label', keywords: ['cong ty', 'cty'], extract: 'company_name' },
          ],
        },
        'address.street': {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['address', 'dia chi', 'd/c', 'addrs', 'street'], extract: 'address_street' },
          ],
        },
        'address.city': {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['address', 'dia chi', 'd/c', 'addrs', 'city'], extract: 'address_city' },
          ],
        },
        'address.state': {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['address', 'dia chi', 'd/c', 'addrs', 'state'], extract: 'address_state' },
          ],
        },
        'address.zip_code': {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['address', 'dia chi', 'd/c', 'addrs', 'zip'], extract: 'address_zip' },
          ],
        },
        tax_id: {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['tax id', 'tax code', 'ma so thue', 'so thue', 'tareodo', 'thuc ('], extract: 'tax_code' },
          ],
        },
        iban: {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['iban', 'bank account', 'so tai khoan', 'so ti khoan', 'banh wcoon'], extract: 'value_after_colon' },
          ],
        },
      },
    },
    client: {
      startKeywords: ['client', 'buyer', 'nguoi mua', 'nguoi thua', 'ben mua', 'khach hang'],
      endBefore: ['items', 'totals', 'summary'],
      fields: {
        name: {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['client', 'buyer', 'nguoi mua', 'nguoi thua'], extract: 'value_after_colon' },
            { method: 'keyword_label', keywords: ['ten don vi', 'company', 'conynnyl name', 'don vi mua'], extract: 'value_after_colon' },
          ],
        },
        'address.street': {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['address', 'dia chi', 'd/c', 'addrs', 'street'], extract: 'address_street' },
          ],
        },
        'address.city': {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['address', 'dia chi', 'd/c', 'addrs', 'city'], extract: 'address_city' },
          ],
        },
        'address.state': {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['address', 'dia chi', 'd/c', 'addrs', 'state'], extract: 'address_state' },
          ],
        },
        'address.zip_code': {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['address', 'dia chi', 'd/c', 'addrs', 'zip'], extract: 'address_zip' },
          ],
        },
        tax_id: {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['tax id', 'tax code', 'ma so thue', 'mi so thue', 'so thue', 'tm code'], extract: 'tax_code' },
          ],
        },
      },
    },
    items: {
      numberFormat: 'en',
      startKeywords: ['ten hang hoa', 'name of goods', 'stt', 'items', 'description'],
      endBefore: ['totals', 'summary'],
      fields: {},
      skipHeaderKeywords: [
        'name of goods', 'ten hang', 'so lo', 'lot', 'exp', 'dvt', 'unit',
        'so luong', 'quan', 'don gia', 'unit price', 'thanh tien', 'amount',
        '(no)', 'no.', 'qty', 'um', 'net price', 'net worth', 'vat [%]',
        'gross worth', 'description',
      ],
      itemSchema: {
        no: { type: 'number', default: 0, strategies: [] },
        description: { type: 'string', default: '', strategies: [] },
        quantity: { type: 'number', default: 0, strategies: [] },
        unit: { type: 'string', default: '', strategies: [] },
        net_price: { type: 'number', default: 0, strategies: [] },
        net_worth: { type: 'number', default: 0, strategies: [] },
        vat_percent: { type: 'number', default: 0, strategies: [] },
        gross_worth: { type: 'number', default: 0, strategies: [] },
      },
      numericFields: ['quantity', 'net_price', 'net_worth', 'vat_percent', 'gross_worth'],
    },
    summary: {
      numberFormat: 'en',
      startKeywords: ['cong tien hang', 'total amount', 'summary', 'net worth'],
      endAt: 'document_end',
      fallbackNumericFields: ['net_worth', 'vat', 'gross_worth'],
      fields: {
        vat_percent: {
          type: 'number',
          default: 0,
          strategies: [
            { method: 'keyword_contains', keywords: ['thue suat', 'vat rate', 'vat [%]', 'vat[%]', 'gigt', 'rat rac', 'vat %'], pattern: '(\\d+)\\s*%' },
          ],
        },
        net_worth: {
          type: 'number',
          default: 0,
          strategies: [
            { method: 'keyword_label', keywords: ['net worth', 'cong tien hang', 'cong tien', 'total amount'], excludeKeywords: ['tong', 'thanh toan', 'gross', 'total net'], extract: 'largest_number', checkNextLine: true },
          ],
        },
        vat: {
          type: 'number',
          default: 0,
          strategies: [
            { method: 'keyword_label', keywords: ['vat amount', 'tien thue', 'ten duc gigt', 'vat:'], excludeKeywords: ['thue suat', 'vat [%]', 'vat rate', 'gross', 'net'], extract: 'largest_number', checkNextLine: true },
          ],
        },
        gross_worth: {
          type: 'number',
          default: 0,
          strategies: [
            { method: 'keyword_label', keywords: ['gross worth', 'tong tien thanh toan', 'tong cong', 'grand total'], excludeKeywords: ['net worth'], extract: 'largest_number', checkNextLine: true },
          ],
        },
        'total.net_worth': {
          type: 'number',
          default: 0,
          strategies: [
            { method: 'keyword_label', keywords: ['total net worth', 'tong net'], extract: 'largest_number', checkNextLine: true },
          ],
        },
        'total.vat': {
          type: 'number',
          default: 0,
          strategies: [
            { method: 'keyword_label', keywords: ['total vat', 'tong thue'], extract: 'largest_number', checkNextLine: true },
          ],
        },
        'total.gross_worth': {
          type: 'number',
          default: 0,
          strategies: [
            { method: 'keyword_label', keywords: ['total gross worth', 'total gross', 'tong cong'], extract: 'largest_number', checkNextLine: true },
          ],
        },
        amountInWords: {
          type: 'string',
          default: '',
          strategies: [
            { method: 'keyword_label', keywords: ['bang chu', 'viet bang chu', 'amorar', 'amount in words'], extract: 'value_after_colon' },
          ],
        },
      },
    },
  },
  confidence: {
    maxScore: 0.5,
    fields: [
      { path: 'seller.name', type: 'non_empty' },
      { path: 'seller.tax_id', type: 'non_empty' },
      { path: 'client.name', type: 'non_empty' },
      { path: 'invoice_no', type: 'non_empty' },
      { path: 'date_of_issue', type: 'non_empty' },
      { path: 'summary.gross_worth', type: 'non_zero' },
    ],
  },
};

// ─── Prescription template ──────────────────────────────────────────
const prescriptionTemplate: DocumentTemplate = {
  name: 'prescription',
  version: 1,
  detection: {
    keywords: ['don thuoc', 'prescription', 'benh nhan', 'chan doan'],
  },
  sections: {
    patient: {
      startAt: 'document_start',
      endBefore: ['doctor'],
      fields: {
        name: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['ho ten', 'benh nhan', 'patient', 'patient name'], extract: 'value_after_colon', scope: 'full_text' }] },
        age: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['tuoi', 'age'], extract: 'value_after_colon', scope: 'full_text' }] },
        gender: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['gioi tinh', 'gender', 'sex'], extract: 'value_after_colon', scope: 'full_text' }] },
        address: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['dia chi', 'address'], extract: 'value_after_colon', scope: 'full_text' }] },
        diagnosis: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['chan doan', 'diagnosis'], extract: 'value_after_colon', scope: 'full_text' }] },
      },
    },
    doctor: {
      startKeywords: ['bac si', 'doctor', 'bs.', 'bs:'],
      endAt: 'document_end',
      fields: {
        name: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['bac si', 'doctor', 'bs.', 'bs:'], extract: 'value_after_colon', scope: 'full_text' }] },
        department: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['khoa', 'department'], extract: 'value_after_colon', scope: 'full_text' }] },
        hospital: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['benh vien', 'hospital', 'phong kham', 'clinic'], extract: 'value_after_colon', scope: 'full_text' }] },
      },
    },
    medications: {
      startAt: 'document_start',
      endAt: 'document_end',
      fields: {},
    },
    meta: {
      startAt: 'document_start',
      endAt: 'document_end',
      fields: {
        date: { type: 'string', default: '', strategies: [{ method: 'regex', pattern: '(\\d{2}/\\d{2}/\\d{4})', scope: 'full_text' }] },
        notes: { type: 'string', default: '', strategies: [] },
      },
    },
  },
  confidence: {
    maxScore: 0.3,
    fields: [
      { path: 'patient.name', type: 'non_empty' },
      { path: 'patient.diagnosis', type: 'non_empty' },
      { path: 'doctor.name', type: 'non_empty' },
      { path: 'meta.date', type: 'non_empty' },
    ],
  },
};

// ─── Receipt template ───────────────────────────────────────────────
const receiptTemplate: DocumentTemplate = {
  name: 'receipt',
  version: 1,
  detection: {
    keywords: ['phieu thu', 'receipt', 'bien lai', 'cash receipt'],
  },
  sections: {
    vendor: {
      startAt: 'document_start',
      endAt: 'document_end',
      fields: {
        name: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['cua hang', 'store', 'vendor', 'shop'], extract: 'value_after_colon', scope: 'full_text' }] },
        address: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['dia chi', 'address'], extract: 'value_after_colon', scope: 'full_text' }] },
        phone: { type: 'string', default: '', strategies: [{ method: 'regex', pattern: '((?:0|\\+84)\\d[\\d\\s\\.\\-]{7,12})', scope: 'full_text' }] },
      },
    },
    meta: {
      startAt: 'document_start',
      endAt: 'document_end',
      fields: {
        date: { type: 'string', default: '', strategies: [{ method: 'regex', pattern: '(\\d{2}/\\d{2}/\\d{4})', scope: 'full_text' }] },
        receiptNumber: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['so phieu', 'receipt no', 'receipt number', 'so:'], extract: 'value_after_colon', scope: 'full_text' }] },
      },
    },
    totals: {
      startAt: 'document_start',
      endAt: 'document_end',
      fields: {
        subtotal: { type: 'number', default: 0, strategies: [] },
        tax: { type: 'number', default: 0, strategies: [] },
        total: { type: 'number', default: 0, strategies: [{ method: 'keyword_label', keywords: ['tong', 'total', 'tong cong', 'grand total'], extract: 'largest_number', checkNextLine: true, scope: 'full_text' }] },
        paymentMethod: { type: 'string', default: '', strategies: [{ method: 'keyword_label', keywords: ['thanh toan', 'payment', 'hinh thuc'], extract: 'value_after_colon', scope: 'full_text' }] },
      },
    },
  },
  confidence: {
    maxScore: 0.25,
    fields: [
      { path: 'vendor.name', type: 'non_empty' },
      { path: 'meta.date', type: 'non_empty' },
      { path: 'totals.total', type: 'non_zero' },
    ],
  },
};

// ─── Generic template ───────────────────────────────────────────────
const genericTemplate: DocumentTemplate = {
  name: 'generic',
  version: 1,
  detection: {
    keywords: [],
  },
  sections: {
    content: {
      startAt: 'document_start',
      endAt: 'document_end',
      fields: {},
    },
  },
  confidence: {
    maxScore: 0.2,
    fields: [],
  },
};

// ─── Built-in templates, ordered by specificity ─────────────────────
export const builtinTemplates: DocumentTemplate[] = [
  invoiceTemplate,
  prescriptionTemplate,
  receiptTemplate,
  genericTemplate,
];

/**
 * Registry for user-provided custom templates.
 */
const customTemplateRegistry: DocumentTemplate[] = [];

/**
 * Register a custom template from a pre-parsed object.
 */
export function registerTemplateObject(template: DocumentTemplate): void {
  const existingIdx = customTemplateRegistry.findIndex(t => t.name === template.name);
  if (existingIdx >= 0) {
    customTemplateRegistry[existingIdx] = template;
  } else {
    customTemplateRegistry.push(template);
  }
}

/**
 * Remove a registered custom template by name.
 */
export function unregisterTemplate(name: string): boolean {
  const idx = customTemplateRegistry.findIndex(t => t.name === name);
  if (idx >= 0) {
    customTemplateRegistry.splice(idx, 1);
    return true;
  }
  return false;
}

/**
 * Get all registered custom templates.
 */
export function getCustomTemplates(): readonly DocumentTemplate[] {
  return customTemplateRegistry;
}

/**
 * Get all available templates (built-in + custom).
 * Custom templates are checked first, allowing users to override built-in ones.
 */
export function getAllTemplates(): DocumentTemplate[] {
  return [...customTemplateRegistry, ...builtinTemplates];
}
