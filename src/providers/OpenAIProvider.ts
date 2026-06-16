import type { AIProvider, AIProviderConfig, ExtractionInput, ExtractionOutput } from './types';
import { extractJSON } from '../utils/json';

const OPENAI_CHAT_URL = 'https://api.openai.com/v1/chat/completions';
const DEFAULT_MODEL = 'gpt-4o';

/**
 * OpenAI provider — sends the image + schema prompt in a single vision API call.
 */
export class OpenAIProvider implements AIProvider {
  readonly name = 'openai';
  private config: AIProviderConfig;
  private model: string;

  constructor(config: AIProviderConfig) {
    this.config = config;
    this.model = config.model ?? DEFAULT_MODEL;
  }

  async extract(input: ExtractionInput, signal?: AbortSignal): Promise<ExtractionOutput> {
    const schemaPrompt = input.customPrompt || input.schemaPrompt;
    const dataUri = `data:${input.imageMimeType};base64,${input.imageBase64}`;

    const chatUrl = this.config.baseUrl
      ? `${this.config.baseUrl}/chat/completions`
      : OPENAI_CHAT_URL;

    const response = await fetch(chatUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.config.apiKey}`,
        ...this.config.headers,
      },
      body: JSON.stringify({
        model: this.model,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: input.systemPrompt },
          {
            role: 'user',
            content: [
              { type: 'text', text: schemaPrompt },
              { type: 'image_url', image_url: { url: dataUri } },
            ],
          },
        ],
        max_tokens: this.config.maxTokens ?? 4096,
      }),
      signal,
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`OpenAI error ${response.status}: ${errorBody}`);
    }

    const data = await response.json();
    const text: string = data.choices?.[0]?.message?.content ?? '';
    let jsonString = extractJSON(text);

    const parsed = JSON.parse(jsonString);
    let detectedDocumentType: string | undefined;
    if (input.documentType === 'auto' && parsed._documentType) {
      detectedDocumentType = parsed._documentType;
      delete parsed._documentType;
      jsonString = JSON.stringify(parsed);
    }

    return {
      jsonString,
      rawText: text,
      detectedDocumentType,
    };
  }
}
