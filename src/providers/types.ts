/**
 * Configuration for an AI provider (API-based).
 */
export interface AIProviderConfig {
  apiKey: string;
  model?: string;
  baseUrl?: string;
  headers?: Record<string, string>;
  maxTokens?: number;
}

/**
 * Input supplied to a provider's extract() method.
 */
export interface ExtractionInput {
  imageUri: string;
  imageBase64: string;
  imageMimeType: string;
  documentType: string;
  language: string;
  schemaPrompt: string;
  systemPrompt: string;
  customPrompt?: string;
}

/**
 * Output returned from a provider's extract() method.
 */
export interface ExtractionOutput {
  jsonString: string;
  rawText: string;
  detectedDocumentType?: string;
  metadata?: Record<string, unknown>;
}

/**
 * Interface every AI provider must implement.
 */
export interface AIProvider {
  /** Human-readable provider name (e.g. 'mistral', 'openai'). */
  readonly name: string;
  /** Run extraction and return structured output. */
  extract(input: ExtractionInput, signal?: AbortSignal): Promise<ExtractionOutput>;
}
