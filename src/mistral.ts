const MISTRAL_OCR_URL = 'https://api.mistral.ai/v1/ocr';
const MISTRAL_CHAT_URL = 'https://api.mistral.ai/v1/chat/completions';
const OCR_MODEL = 'mistral-ocr-latest';
const CHAT_MODEL = 'mistral-small-latest';

// --- Utilities ---

async function fileToBase64(uri: string): Promise<string> {
  const response = await fetch(uri);
  const blob = await response.blob();
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => {
      const result = reader.result as string;
      const base64 = result.split(',')[1];
      resolve(base64);
    };
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

export function extractJSON(text: string): string {
  const trimmed = text.trim();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return trimmed;
  }
  // Try ```json ... ``` blocks
  const jsonBlockMatch = trimmed.match(/```json\s*\n([\s\S]*?)\n```/);
  if (jsonBlockMatch) {
    return jsonBlockMatch[1].trim();
  }
  // Try ``` ... ``` blocks
  const codeBlockMatch = trimmed.match(/```\s*\n([\s\S]*?)\n```/);
  if (codeBlockMatch) {
    return codeBlockMatch[1].trim();
  }
  // Last resort: first { to last }
  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start !== -1 && end !== -1) {
    return trimmed.slice(start, end + 1);
  }
  return trimmed;
}

// --- Document Prompts ---

function getSystemPrompt(language: string): string {
  const lang = language === 'vi' ? 'Vietnamese' : 'English';
  return `You are a document data extraction specialist. Extract structured data from OCR text.
The document is primarily in ${lang}. Return ONLY valid JSON, no markdown, no explanation.
If a field cannot be found, use empty string "" for strings, 0 for numbers, and [] for arrays.
Be precise with numbers: preserve the exact format from the source text for amounts and codes.`;
}

const SCHEMA_PROMPTS: Record<string, string> = {
  invoice: `Extract the following JSON structure from this invoice/hoa don:
{
  "seller": { "companyName": "", "taxCode": "", "address": "", "phone": "", "bankAccount": "" },
  "buyer": { "companyName": "", "taxCode": "", "address": "" },
  "metadata": { "serial": "", "number": "", "date": "DD/MM/YYYY", "form": "" },
  "items": [{ "stt": 1, "productName": "", "lotNumber": "", "expiryDate": "", "unit": "", "quantity": 0, "unitPrice": 0, "amount": 0 }],
  "totals": { "subtotal": 0, "vatRate": 0, "vatAmount": 0, "totalPayment": 0, "amountInWords": "" }
}`,
  prescription: `Extract the following JSON structure from this prescription/don thuoc:
{
  "patient": { "name": "", "age": "", "gender": "", "address": "", "diagnosis": "" },
  "doctor": { "name": "", "department": "", "hospital": "" },
  "medications": [{ "name": "", "dosage": "", "quantity": "", "instructions": "" }],
  "date": "DD/MM/YYYY",
  "notes": ""
}`,
  receipt: `Extract the following JSON structure from this receipt/phieu thu:
{
  "vendor": { "name": "", "address": "", "phone": "" },
  "date": "DD/MM/YYYY",
  "receiptNumber": "",
  "items": [{ "name": "", "quantity": 0, "unitPrice": 0, "amount": 0 }],
  "subtotal": 0, "tax": 0, "total": 0, "paymentMethod": ""
}`,
  purchase_order: `Extract the following JSON structure from this purchase order/don dat hang:
{
  "orderNumber": "", "date": "DD/MM/YYYY",
  "supplier": { "name": "", "address": "", "phone": "" },
  "buyer": { "name": "", "address": "", "phone": "" },
  "items": [{ "name": "", "quantity": 0, "unitPrice": 0, "amount": 0, "unit": "" }],
  "totalAmount": 0, "notes": ""
}`,
  delivery_note: `Extract the following JSON structure from this delivery note/phieu giao hang:
{
  "deliveryNumber": "", "date": "DD/MM/YYYY",
  "sender": { "name": "", "address": "" },
  "receiver": { "name": "", "address": "" },
  "items": [{ "name": "", "quantity": 0, "unit": "", "lotNumber": "", "expiryDate": "" }],
  "notes": ""
}`,
  certificate: `Extract the following JSON structure from this certificate/giay chung nhan:
{
  "type": "", "certificateNumber": "", "issuedTo": "", "issuedBy": "",
  "issueDate": "DD/MM/YYYY", "expiryDate": "DD/MM/YYYY", "details": ""
}`,
  auto: `Detect the document type and extract structured data.
You MUST set "_documentType" to exactly one of: "invoice", "prescription", "receipt", "purchase_order", "delivery_note", "certificate".
Always pick the most appropriate type based on the content. Never use "unknown" or any other value.

Use the corresponding JSON structure based on the detected type:

For invoice/bill/hoa don:
{
  "_documentType": "invoice",
  "seller": { "companyName": "", "taxCode": "", "address": "", "phone": "", "bankAccount": "" },
  "buyer": { "companyName": "", "taxCode": "", "address": "" },
  "metadata": { "serial": "", "number": "", "date": "DD/MM/YYYY", "form": "" },
  "items": [{ "stt": 1, "productName": "", "lotNumber": "", "expiryDate": "", "unit": "", "quantity": 0, "unitPrice": 0, "amount": 0 }],
  "totals": { "subtotal": 0, "vatRate": 0, "vatAmount": 0, "totalPayment": 0, "amountInWords": "" }
}

For prescription/don thuoc:
{
  "_documentType": "prescription",
  "patient": { "name": "", "age": "", "gender": "", "address": "", "diagnosis": "" },
  "doctor": { "name": "", "department": "", "hospital": "" },
  "medications": [{ "name": "", "dosage": "", "quantity": "", "instructions": "" }],
  "date": "DD/MM/YYYY",
  "notes": ""
}

For receipt/phieu thu:
{
  "_documentType": "receipt",
  "vendor": { "name": "", "address": "", "phone": "" },
  "date": "DD/MM/YYYY",
  "receiptNumber": "",
  "items": [{ "name": "", "quantity": 0, "unitPrice": 0, "amount": 0 }],
  "subtotal": 0, "tax": 0, "total": 0, "paymentMethod": ""
}

For purchase_order/don dat hang:
{
  "_documentType": "purchase_order",
  "orderNumber": "", "date": "DD/MM/YYYY",
  "supplier": { "name": "", "address": "", "phone": "" },
  "buyer": { "name": "", "address": "", "phone": "" },
  "items": [{ "name": "", "quantity": 0, "unitPrice": 0, "amount": 0, "unit": "" }],
  "totalAmount": 0, "notes": ""
}

For delivery_note/phieu giao hang:
{
  "_documentType": "delivery_note",
  "deliveryNumber": "", "date": "DD/MM/YYYY",
  "sender": { "name": "", "address": "" },
  "receiver": { "name": "", "address": "" },
  "items": [{ "name": "", "quantity": 0, "unit": "", "lotNumber": "", "expiryDate": "" }],
  "notes": ""
}

For certificate/giay chung nhan:
{
  "_documentType": "certificate",
  "type": "", "certificateNumber": "", "issuedTo": "", "issuedBy": "",
  "issueDate": "DD/MM/YYYY", "expiryDate": "DD/MM/YYYY", "details": ""
}`,
};

function getSchemaPrompt(documentType: string): string {
  return SCHEMA_PROMPTS[documentType] ?? SCHEMA_PROMPTS.auto!;
}

// --- Mistral OCR ---

export async function mistralOcr(
  apiKey: string,
  imageUri: string,
  signal?: AbortSignal,
): Promise<string> {
  const base64 = await fileToBase64(imageUri);
  const dataUri = `data:image/jpeg;base64,${base64}`;

  const response = await fetch(MISTRAL_OCR_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: OCR_MODEL,
      document: {
        type: 'image_url',
        image_url: dataUri,
      },
    }),
    signal,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Mistral OCR error ${response.status}: ${errorBody}`);
  }

  const data = await response.json();
  const pages: Array<{ markdown: string; index: number }> = data.pages ?? [];
  return pages.map(p => p.markdown).join('\n\n');
}

// --- Mistral Chat (JSON extraction) ---

export async function mistralExtractJson(
  apiKey: string,
  ocrText: string,
  documentType: string,
  language: string,
  customPrompt?: string,
  signal?: AbortSignal,
): Promise<{ jsonString: string; detectedDocumentType?: string }> {
  const systemPrompt = getSystemPrompt(language);
  const schemaPrompt = customPrompt || getSchemaPrompt(documentType);

  const userContent = `${schemaPrompt}\n\nOCR Text:\n${ocrText}`;

  const response = await fetch(MISTRAL_CHAT_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: CHAT_MODEL,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userContent },
      ],
      max_tokens: 4096,
    }),
    signal,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Mistral Chat error ${response.status}: ${errorBody}`);
  }

  const data = await response.json();
  const text: string = data.choices?.[0]?.message?.content ?? '';
  let jsonString = extractJSON(text);

  // Validate JSON
  const parsed = JSON.parse(jsonString);

  let detectedDocumentType: string | undefined;
  if (documentType === 'auto' && parsed._documentType) {
    detectedDocumentType = parsed._documentType;
    // Strip _documentType from the output data to keep it clean
    delete parsed._documentType;
    jsonString = JSON.stringify(parsed);
  }

  return { jsonString, detectedDocumentType };
}

// --- Combined: Image → OCR → JSON ---

const VALID_DOC_TYPES = [
  'invoice',
  'prescription',
  'receipt',
  'purchase_order',
  'delivery_note',
  'certificate',
];

export interface MistralExtractionResult {
  documentType: string;
  data: string;
  rawText: string;
  confidence: number;
  extractionMethod: string;
  processingTimeMs: number;
  ocrTimeMs: number;
  warnings: string[];
}

export async function extractWithMistral(
  apiKey: string,
  imageUri: string,
  documentType: string,
  language: string,
  customPrompt?: string,
  signal?: AbortSignal,
): Promise<MistralExtractionResult> {
  const startTime = Date.now();

  // Step 1: Mistral OCR
  const ocrText = await mistralOcr(apiKey, imageUri, signal);
  const ocrTimeMs = Date.now() - startTime;

  // Step 2: Mistral Chat for JSON extraction
  const result = await mistralExtractJson(
    apiKey,
    ocrText,
    documentType,
    language,
    customPrompt,
    signal,
  );

  const processingTimeMs = Date.now() - startTime;
  let resolvedType = result.detectedDocumentType ?? documentType;

  // Validate resolved type — fall back to 'invoice' for unknown/invalid types
  if (!VALID_DOC_TYPES.includes(resolvedType)) {
    resolvedType = 'invoice';
  }

  // Compute dynamic confidence based on JSON parse success and field count
  const confidence = computeMistralConfidence(result.jsonString);

  return {
    documentType: resolvedType,
    data: result.jsonString,
    rawText: ocrText,
    confidence,
    extractionMethod: 'mistral',
    processingTimeMs,
    ocrTimeMs,
    warnings: [],
  };
}

export function computeMistralConfidence(jsonString: string): number {
  try {
    const parsed = JSON.parse(jsonString);
    if (!parsed || typeof parsed !== 'object') return 0.5;

    // Count non-empty fields
    const fields = Object.keys(parsed);
    let filledCount = 0;
    for (const key of fields) {
      const val = parsed[key];
      if (val === '' || val === 0 || val === null || val === undefined) continue;
      if (Array.isArray(val) && val.length === 0) continue;
      filledCount++;
    }

    if (fields.length === 0) return 0.5;

    const fillRatio = filledCount / fields.length;
    // Base confidence 0.7, scaled up by fill ratio to max 0.95
    return Math.min(0.95, 0.7 + fillRatio * 0.25);
  } catch {
    // JSON parse failed — low confidence
    return 0.4;
  }
}
