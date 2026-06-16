import type { DocumentSchema } from './types';

export const BUILT_IN_SCHEMAS: DocumentSchema[] = [
  {
    key: 'invoice',
    label: 'Invoice',
    description: 'VAT invoice / Hoa don',
    structure: {
      seller: { companyName: '', taxCode: '', address: '', phone: '', bankAccount: '' },
      buyer: { companyName: '', taxCode: '', address: '' },
      metadata: { serial: '', number: '', date: 'DD/MM/YYYY', form: '' },
      items: [{ stt: 1, productName: '', lotNumber: '', expiryDate: '', unit: '', quantity: 0, unitPrice: 0, amount: 0 }],
      totals: { subtotal: 0, vatRate: 0, vatAmount: 0, totalPayment: 0, amountInWords: '' },
    },
  },
  {
    key: 'prescription',
    label: 'Prescription',
    description: 'Medical prescription / Don thuoc',
    structure: {
      patient: { name: '', age: '', gender: '', address: '', diagnosis: '' },
      doctor: { name: '', department: '', hospital: '' },
      medications: [{ name: '', dosage: '', quantity: '', instructions: '' }],
      date: 'DD/MM/YYYY',
      notes: '',
    },
  },
  {
    key: 'receipt',
    label: 'Receipt',
    description: 'Sales receipt / Phieu thu',
    structure: {
      vendor: { name: '', address: '', phone: '' },
      date: 'DD/MM/YYYY',
      receiptNumber: '',
      items: [{ name: '', quantity: 0, unitPrice: 0, amount: 0 }],
      subtotal: 0,
      tax: 0,
      total: 0,
      paymentMethod: '',
    },
  },
  {
    key: 'purchase_order',
    label: 'Purchase Order',
    description: 'Purchase order / Don dat hang',
    structure: {
      orderNumber: '',
      date: 'DD/MM/YYYY',
      supplier: { name: '', address: '', phone: '' },
      buyer: { name: '', address: '', phone: '' },
      items: [{ name: '', quantity: 0, unitPrice: 0, amount: 0, unit: '' }],
      totalAmount: 0,
      notes: '',
    },
  },
  {
    key: 'delivery_note',
    label: 'Delivery Note',
    description: 'Delivery note / Phieu giao hang',
    structure: {
      deliveryNumber: '',
      date: 'DD/MM/YYYY',
      sender: { name: '', address: '' },
      receiver: { name: '', address: '' },
      items: [{ name: '', quantity: 0, unit: '', lotNumber: '', expiryDate: '' }],
      notes: '',
    },
  },
  {
    key: 'certificate',
    label: 'Certificate',
    description: 'Certificate / Giay chung nhan',
    structure: {
      type: '',
      certificateNumber: '',
      issuedTo: '',
      issuedBy: '',
      issueDate: 'DD/MM/YYYY',
      expiryDate: 'DD/MM/YYYY',
      details: '',
    },
  },
];
