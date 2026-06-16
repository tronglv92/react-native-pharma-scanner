import type { AIProvider, AIProviderConfig, ExtractionInput, ExtractionOutput } from './types';
import { extractJSON } from '../utils/json';

const MISTRAL_OCR_URL = 'https://api.mistral.ai/v1/ocr';
const MISTRAL_CHAT_URL = 'https://api.mistral.ai/v1/chat/completions';
const DEFAULT_OCR_MODEL = 'mistral-ocr-latest';
const DEFAULT_CHAT_MODEL = 'mistral-small-latest';

/**
 * Mistral AI provider — uses a 2-step pipeline:
 * 1. Mistral OCR to extract text from the image.
 * 2. Mistral Chat to extract structured JSON from the OCR text.
 */
export class MistralProvider implements AIProvider {
  readonly name = 'mistral';
  private config: AIProviderConfig;
  private ocrModel: string;
  private chatModel: string;

  constructor(config: AIProviderConfig) {
    this.config = config;
    this.ocrModel = DEFAULT_OCR_MODEL;
    this.chatModel = config.model ?? DEFAULT_CHAT_MODEL;
  }

  async extract(input: ExtractionInput, signal?: AbortSignal): Promise<ExtractionOutput> {
    // Step 1: OCR
    const ocrText = await this.ocr(input.imageBase64, input.imageMimeType, signal);

    // Step 2: Chat extraction
    const schemaPrompt = input.customPrompt || input.schemaPrompt;
    const userContent = `${schemaPrompt}\n\nOCR Text:\n${ocrText}`;

    const chatUrl = this.config.baseUrl
      ? `${this.config.baseUrl}/chat/completions`
      : MISTRAL_CHAT_URL;

    const response = await fetch(chatUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.config.apiKey}`,
        ...this.config.headers,
      },
      body: JSON.stringify({
        model: this.chatModel,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: input.systemPrompt },
          { role: 'user', content: userContent },
        ],
        max_tokens: this.config.maxTokens ?? 4096,
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

    // Validate JSON and handle auto-detect
    const parsed = JSON.parse(jsonString);
    let detectedDocumentType: string | undefined;
    if (input.documentType === 'auto' && parsed._documentType) {
      detectedDocumentType = parsed._documentType;
      delete parsed._documentType;
      jsonString = JSON.stringify(parsed);
    }

    return {
      jsonString,
      rawText: ocrText,
      detectedDocumentType,
    };
  }

  private async ocr(imageBase64: string, mimeType: string, signal?: AbortSignal): Promise<string> {
    const dataUri = `data:${mimeType};base64,${imageBase64}`;
    const ocrUrl = this.config.baseUrl
      ? `${this.config.baseUrl.replace(/\/chat\/completions$/, '')}/ocr`
      : MISTRAL_OCR_URL;

    const response = await fetch(ocrUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.config.apiKey}`,
        ...this.config.headers,
      },
      body: JSON.stringify({
        model: this.ocrModel,
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
}
