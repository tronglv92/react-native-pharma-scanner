import { NitroModules } from 'react-native-nitro-modules';
import type { PharmaScanner } from '../specs/PharmaScanner.nitro';
import type { AIProvider, ExtractionInput, ExtractionOutput } from './types';

/**
 * Local LLM provider — delegates to the native scanner.extractDocument()
 * method with the special '__local_llm__' customPrompt flag.
 *
 * This provider does not need an API key; it runs on-device.
 */
export class LocalLlmProvider implements AIProvider {
  readonly name = 'local_llm';
  private scanner: PharmaScanner;

  constructor() {
    this.scanner = NitroModules.createHybridObject<PharmaScanner>('PharmaScanner');
  }

  async extract(input: ExtractionInput, _signal?: AbortSignal): Promise<ExtractionOutput> {
    const result = await this.scanner.extractDocument(input.imageUri, {
      documentType: input.documentType,
      language: input.language,
      customPrompt: '__local_llm__',
      forceOffline: true,
    });

    return {
      jsonString: result.data,
      rawText: result.rawText,
      detectedDocumentType:
        input.documentType === 'auto' && result.documentType !== 'auto'
          ? result.documentType
          : undefined,
      metadata: {
        extractionMethod: result.extractionMethod,
        ocrTimeMs: result.ocrTimeMs,
        processingTimeMs: result.processingTimeMs,
      },
    };
  }
}
