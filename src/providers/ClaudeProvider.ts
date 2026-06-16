import type { AIProvider, AIProviderConfig, ExtractionInput, ExtractionOutput } from './types';
import { extractJSON } from '../utils/json';

const CLAUDE_API_URL = 'https://api.anthropic.com/v1/messages';
const DEFAULT_MODEL = 'claude-sonnet-4-20250514';

/**
 * Claude (Anthropic) provider — sends the image + schema prompt in a single
 * vision API call using the Anthropic Messages API.
 */
export class ClaudeProvider implements AIProvider {
  readonly name = 'claude';
  private config: AIProviderConfig;
  private model: string;

  constructor(config: AIProviderConfig) {
    this.config = config;
    this.model = config.model ?? DEFAULT_MODEL;
  }

  async extract(input: ExtractionInput, signal?: AbortSignal): Promise<ExtractionOutput> {
    const schemaPrompt = input.customPrompt || input.schemaPrompt;

    const apiUrl = this.config.baseUrl ?? CLAUDE_API_URL;

    const response = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': this.config.apiKey,
        'anthropic-version': '2023-06-01',
        ...this.config.headers,
      },
      body: JSON.stringify({
        model: this.model,
        max_tokens: this.config.maxTokens ?? 4096,
        system: input.systemPrompt,
        messages: [
          {
            role: 'user',
            content: [
              {
                type: 'image',
                source: {
                  type: 'base64',
                  media_type: input.imageMimeType,
                  data: input.imageBase64,
                },
              },
              {
                type: 'text',
                text: schemaPrompt,
              },
            ],
          },
        ],
      }),
      signal,
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`Claude error ${response.status}: ${errorBody}`);
    }

    const data = await response.json();
    const textBlock = data.content?.find(
      (block: { type: string }) => block.type === 'text',
    );
    const text: string = textBlock?.text ?? '';
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
