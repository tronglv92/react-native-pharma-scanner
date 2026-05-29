// TypeScript-only interfaces for each document type's `data` JSON.
// These are NOT bridged via Nitro — they parse the JSON string from DocumentExtractionResult.data.

export interface InvoiceData {
  seller: {
    companyName: string;
    taxCode: string;
    address: string;
    phone: string;
    bankAccount: string;
  };
  buyer: {
    companyName: string;
    taxCode: string;
    address: string;
  };
  metadata: {
    serial: string;
    number: string;
    date: string;
    form: string;
  };
  items: Array<{
    stt: number;
    productName: string;
    lotNumber: string;
    expiryDate: string;
    unit: string;
    quantity: number;
    unitPrice: number;
    amount: number;
  }>;
  totals: {
    subtotal: number;
    vatRate: number;
    vatAmount: number;
    totalPayment: number;
    amountInWords: string;
  };
}

export interface PrescriptionData {
  patient: {
    name: string;
    age: string;
    gender: string;
    address: string;
    diagnosis: string;
  };
  doctor: {
    name: string;
    department: string;
    hospital: string;
  };
  medications: Array<{
    name: string;
    dosage: string;
    quantity: string;
    instructions: string;
  }>;
  date: string;
  notes: string;
}

export interface ReceiptData {
  vendor: {
    name: string;
    address: string;
    phone: string;
  };
  date: string;
  receiptNumber: string;
  items: Array<{
    name: string;
    quantity: number;
    unitPrice: number;
    amount: number;
  }>;
  subtotal: number;
  tax: number;
  total: number;
  paymentMethod: string;
}

export interface PurchaseOrderData {
  orderNumber: string;
  date: string;
  supplier: {
    name: string;
    address: string;
    phone: string;
  };
  buyer: {
    name: string;
    address: string;
    phone: string;
  };
  items: Array<{
    name: string;
    quantity: number;
    unitPrice: number;
    amount: number;
    unit: string;
  }>;
  totalAmount: number;
  notes: string;
}

export interface DeliveryNoteData {
  deliveryNumber: string;
  date: string;
  sender: {
    name: string;
    address: string;
  };
  receiver: {
    name: string;
    address: string;
  };
  items: Array<{
    name: string;
    quantity: number;
    unit: string;
    lotNumber: string;
    expiryDate: string;
  }>;
  notes: string;
}

export interface CertificateData {
  type: string;
  certificateNumber: string;
  issuedTo: string;
  issuedBy: string;
  issueDate: string;
  expiryDate: string;
  details: string;
}

export interface DocumentTypeInfo {
  key: string;
  label: string;
  description: string;
}

export const DOCUMENT_TYPES: DocumentTypeInfo[] = [
  { key: 'auto', label: 'Auto Detect', description: 'Automatically detect document type' },
  { key: 'invoice', label: 'Invoice', description: 'VAT invoice / Hoa don' },
  { key: 'prescription', label: 'Prescription', description: 'Medical prescription / Don thuoc' },
  { key: 'receipt', label: 'Receipt', description: 'Sales receipt / Phieu thu' },
  { key: 'purchase_order', label: 'Purchase Order', description: 'Purchase order / Don dat hang' },
  { key: 'delivery_note', label: 'Delivery Note', description: 'Delivery note / Phieu giao hang' },
  { key: 'certificate', label: 'Certificate', description: 'Certificate / Giay chung nhan' },
];

export function parseDocumentData<T = unknown>(jsonString: string): T | null {
  try {
    return JSON.parse(jsonString) as T;
  } catch {
    return null;
  }
}
