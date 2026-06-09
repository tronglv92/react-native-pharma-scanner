import type {
  InvoiceData,
  PrescriptionData,
  ReceiptData,
  DeliveryNoteData,
  CertificateData,
} from '../document-types';

export type ValidationSeverity = 'error' | 'warning' | 'info';

export interface ValidationIssue {
  field: string;
  code: string;
  severity: ValidationSeverity;
  message: string;
}

export interface ValidationResult {
  issues: ValidationIssue[];
  isValid: boolean;
}

/**
 * Parse a date string in DD/MM/YYYY, MM/YYYY, or YYYY-MM-DD format.
 * Returns a Date or null if unparseable.
 */
function parseDate(dateStr: string): Date | null {
  if (!dateStr || typeof dateStr !== 'string') return null;
  const trimmed = dateStr.trim();

  // YYYY-MM-DD
  const isoMatch = trimmed.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (isoMatch) {
    const d = new Date(
      parseInt(isoMatch[1], 10),
      parseInt(isoMatch[2], 10) - 1,
      parseInt(isoMatch[3], 10),
    );
    return isNaN(d.getTime()) ? null : d;
  }

  // DD/MM/YYYY
  const dmy = trimmed.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (dmy) {
    const d = new Date(
      parseInt(dmy[3], 10),
      parseInt(dmy[2], 10) - 1,
      parseInt(dmy[1], 10),
    );
    return isNaN(d.getTime()) ? null : d;
  }

  // MM/YYYY
  const my = trimmed.match(/^(\d{1,2})\/(\d{4})$/);
  if (my) {
    // Last day of the month
    const month = parseInt(my[1], 10);
    const year = parseInt(my[2], 10);
    const d = new Date(year, month, 0); // day 0 of next month = last day of this month
    return isNaN(d.getTime()) ? null : d;
  }

  return null;
}

export function validateExpiryDate(
  dateStr: string | undefined | null,
  fieldName: string,
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  if (!dateStr) return issues;

  const date = parseDate(dateStr);
  if (!date) {
    issues.push({
      field: fieldName,
      code: 'INVALID_DATE_FORMAT',
      severity: 'warning',
      message: `${fieldName}: "${dateStr}" is not a recognized date format (DD/MM/YYYY, MM/YYYY, or YYYY-MM-DD)`,
    });
    return issues;
  }

  const now = new Date();
  if (date < now) {
    issues.push({
      field: fieldName,
      code: 'EXPIRED',
      severity: 'error',
      message: `${fieldName}: "${dateStr}" is expired`,
    });
  } else {
    const sixMonths = new Date();
    sixMonths.setMonth(sixMonths.getMonth() + 6);
    if (date < sixMonths) {
      issues.push({
        field: fieldName,
        code: 'EXPIRING_SOON',
        severity: 'warning',
        message: `${fieldName}: "${dateStr}" expires within 6 months`,
      });
    }
  }

  return issues;
}

export function validateLotNumber(
  lotNumber: string | undefined | null,
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  if (!lotNumber || lotNumber.trim() === '') {
    issues.push({
      field: 'lotNumber',
      code: 'EMPTY_LOT_NUMBER',
      severity: 'warning',
      message: 'Lot number is empty',
    });
    return issues;
  }

  const trimmed = lotNumber.trim();

  if (trimmed.length < 4 || trimmed.length > 20) {
    issues.push({
      field: 'lotNumber',
      code: 'INVALID_LOT_LENGTH',
      severity: 'warning',
      message: `Lot number "${trimmed}" should be 4-20 characters`,
    });
  }

  if (!/^[a-zA-Z0-9\-_.]+$/.test(trimmed)) {
    issues.push({
      field: 'lotNumber',
      code: 'INVALID_LOT_CHARS',
      severity: 'warning',
      message: `Lot number "${trimmed}" contains non-alphanumeric characters`,
    });
  }

  if (/^0+$/.test(trimmed)) {
    issues.push({
      field: 'lotNumber',
      code: 'SUSPICIOUS_LOT',
      severity: 'warning',
      message: `Lot number "${trimmed}" is suspicious (all zeros)`,
    });
  }

  return issues;
}

export function validateTaxId(
  taxId: string | undefined | null,
  country: string = 'vi',
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  if (!taxId || taxId.trim() === '') return issues;

  const cleaned = taxId.replace(/[\s\-\.]/g, '');

  if (country === 'vi') {
    // Vietnamese tax code: 10 or 13 digits
    if (!/^\d{10}$/.test(cleaned) && !/^\d{13}$/.test(cleaned)) {
      issues.push({
        field: 'taxCode',
        code: 'INVALID_TAX_FORMAT',
        severity: 'warning',
        message: `Tax code "${taxId}" should be 10 or 13 digits for Vietnam`,
      });
      return issues;
    }

    // Check digit validation (weighted sum mod 10 for first 10 digits)
    const weights = [31, 29, 23, 19, 17, 13, 7, 5, 3, 1];
    const digits = cleaned.slice(0, 10).split('').map(Number);
    let sum = 0;
    for (let i = 0; i < 10; i++) {
      sum += digits[i] * weights[i];
    }
    if (sum % 10 !== 0) {
      issues.push({
        field: 'taxCode',
        code: 'INVALID_TAX_CHECK_DIGIT',
        severity: 'warning',
        message: `Tax code "${taxId}" has an invalid check digit`,
      });
    }
  }

  return issues;
}

export function validateAmountCrossCheck(
  items: Array<{ amount?: number }> | undefined | null,
  total: number | undefined | null,
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  if (!items || items.length === 0 || total == null || total === 0)
    return issues;

  const sum = items.reduce((acc, item) => acc + (item.amount ?? 0), 0);
  const diff = Math.abs(sum - total);

  // Tolerance of 1 unit
  if (diff > 1) {
    issues.push({
      field: 'totals',
      code: 'AMOUNT_MISMATCH',
      severity: 'warning',
      message: `Sum of item amounts (${sum}) does not match total (${total}), difference: ${diff}`,
    });
  }

  return issues;
}

export function validateDocumentData(
  documentType: string,
  data: unknown,
): ValidationResult {
  const issues: ValidationIssue[] = [];

  if (!data || typeof data !== 'object') {
    return { issues, isValid: true };
  }

  switch (documentType) {
    case 'invoice':
      validateInvoice(data as InvoiceData, issues);
      break;
    case 'prescription':
      validatePrescription(data as PrescriptionData, issues);
      break;
    case 'receipt':
      validateReceipt(data as ReceiptData, issues);
      break;
    case 'delivery_note':
      validateDeliveryNote(data as DeliveryNoteData, issues);
      break;
    case 'certificate':
      validateCertificate(data as CertificateData, issues);
      break;
  }

  const isValid = !issues.some(i => i.severity === 'error');
  return { issues, isValid };
}

function validateInvoice(data: InvoiceData, issues: ValidationIssue[]): void {
  // Tax code validation
  if (data.seller?.taxCode) {
    issues.push(...validateTaxId(data.seller.taxCode, 'vi'));
  }
  if (data.buyer?.taxCode) {
    issues.push(...validateTaxId(data.buyer.taxCode, 'vi'));
  }

  // Items validation
  if (data.items && Array.isArray(data.items)) {
    for (let i = 0; i < data.items.length; i++) {
      const item = data.items[i];
      if (item.expiryDate) {
        issues.push(
          ...validateExpiryDate(item.expiryDate, `items[${i}].expiryDate`),
        );
      }
      if (item.lotNumber) {
        const lotIssues = validateLotNumber(item.lotNumber);
        lotIssues.forEach(iss => {
          iss.field = `items[${i}].lotNumber`;
        });
        issues.push(...lotIssues);
      }
    }

    // Amount cross-check
    if (data.totals?.subtotal) {
      issues.push(...validateAmountCrossCheck(data.items, data.totals.subtotal));
    } else if (data.totals?.totalPayment) {
      // If no subtotal, check against totalPayment (less VAT if present)
      const expectedTotal = data.totals.vatAmount
        ? data.totals.totalPayment - data.totals.vatAmount
        : data.totals.totalPayment;
      issues.push(...validateAmountCrossCheck(data.items, expectedTotal));
    }
  }
}

function validatePrescription(
  data: PrescriptionData,
  issues: ValidationIssue[],
): void {
  if (
    !data.medications ||
    !Array.isArray(data.medications) ||
    data.medications.length === 0
  ) {
    issues.push({
      field: 'medications',
      code: 'EMPTY_MEDICATIONS',
      severity: 'warning',
      message: 'Prescription has no medications listed',
    });
  }

  if (data.date) {
    const date = parseDate(data.date);
    if (!date) {
      issues.push({
        field: 'date',
        code: 'INVALID_DATE_FORMAT',
        severity: 'info',
        message: `Prescription date "${data.date}" is not a recognized format`,
      });
    }
  }
}

function validateReceipt(data: ReceiptData, issues: ValidationIssue[]): void {
  if (data.items && data.total) {
    issues.push(...validateAmountCrossCheck(data.items, data.total));
  }
}

function validateDeliveryNote(
  data: DeliveryNoteData,
  issues: ValidationIssue[],
): void {
  if (data.items && Array.isArray(data.items)) {
    for (let i = 0; i < data.items.length; i++) {
      const item = data.items[i];
      if (item.expiryDate) {
        issues.push(
          ...validateExpiryDate(item.expiryDate, `items[${i}].expiryDate`),
        );
      }
      if (item.lotNumber) {
        const lotIssues = validateLotNumber(item.lotNumber);
        lotIssues.forEach(iss => {
          iss.field = `items[${i}].lotNumber`;
        });
        issues.push(...lotIssues);
      }
    }
  }
}

function validateCertificate(
  data: CertificateData,
  issues: ValidationIssue[],
): void {
  if (data.expiryDate) {
    issues.push(...validateExpiryDate(data.expiryDate, 'expiryDate'));
  }
}
