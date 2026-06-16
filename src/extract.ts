import type { AIProvider } from './providers/types';
import type { DocumentExtractionResult } from './specs/types.nitro';
import { fileToBase64, getMimeType } from './utils/image';
import { computeConfidence } from './utils/confidence';
import { getSchema, schemaToPrompt, generateAutoDetectPrompt } from './schemas/registry';

export interface ExtractDocumentOptions {
  documentType?: string;
  language?: string;
  customPrompt?: string;
}

function getSystemPrompt(language: string): string {
  const lang = language === 'vi' ? 'Vietnamese' : 'English';
  return `You are a document data extraction specialist. Extract structured data from OCR text.
The document is primarily in ${lang}. Return ONLY valid JSON, no markdown, no explanation.
If a field cannot be found, use empty string "" for strings, 0 for numbers, and [] for arrays.
Be precise with numbers: preserve the exact format from the source text for amounts and codes.`;
}

const VALID_DOC_TYPES = [
  'invoice',
  'prescription',
  'receipt',
  'purchase_order',
  'delivery_note',
  'certificate',
];

/**
 * High-level extraction function — converts an image to structured JSON
 * using the given AI provider.
 */
export async function extractDocument(
  provider: AIProvider,
  imageUri: string,
  options?: ExtractDocumentOptions,
  signal?: AbortSignal,
): Promise<DocumentExtractionResult> {
  const startTime = Date.now();
  const documentType = options?.documentType ?? 'auto';
  const language = options?.language ?? 'en';

  // Convert image to base64
  const imageBase64 = await fileToBase64(imageUri);
  const imageMimeType = getMimeType(imageUri);

  // Build prompts from schema registry
  let schemaPrompt: string;
  if (documentType === 'auto') {
    schemaPrompt = generateAutoDetectPrompt();
  } else {
    const schema = getSchema(documentType);
    schemaPrompt = schema
      ? schemaToPrompt(schema)
      : generateAutoDetectPrompt();
  }

  const systemPrompt = getSystemPrompt(language);

  // Call the provider
  const result = await provider.extract(
    {
      imageUri,
      imageBase64,
      imageMimeType,
      documentType,
      language,
      schemaPrompt,
      systemPrompt,
      customPrompt: options?.customPrompt,
    },
    signal,
  );

  const processingTimeMs = Date.now() - startTime;

  // Resolve document type
  let resolvedType = result.detectedDocumentType ?? documentType;
  if (!VALID_DOC_TYPES.includes(resolvedType)) {
    // Check if it's a custom-registered schema
    const schema = getSchema(resolvedType);
    if (!schema) {
      resolvedType = 'invoice';
    }
  }

  const confidence = computeConfidence(result.jsonString);

  return {
    documentType: resolvedType,
    data: result.jsonString,
    rawText: result.rawText,
    confidence,
    extractionMethod: provider.name,
    processingTimeMs,
    ocrTimeMs: (result.metadata?.ocrTimeMs as number) ?? 0,
    warnings: [],
  };
}
