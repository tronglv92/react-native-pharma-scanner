/**
 * Public API for the template extraction engine.
 */

export type { DocumentTemplate, TemplateResult, FieldDef, FieldStrategy, SectionDef } from './types';
import type { DocumentTemplate, TemplateResult } from './types';
import { detectDocumentType, extractWithEngine } from './engine';
import { getAllTemplates } from '../templates';

/**
 * Extract structured data from OCR text using template-based extraction.
 *
 * Templates are resolved in this order:
 * 1. `customTemplates` parameter (if provided)
 * 2. User-registered templates (via `registerTemplate()`)
 * 3. Built-in templates (invoice, prescription, receipt, generic)
 *
 * @param ocrText - Raw OCR text from recognizeText/recognizeDocument
 * @param documentType - "auto" to detect, or specific type like "invoice"
 * @param language - Language hint (currently unused, templates handle both vi + en)
 * @param customTemplates - Optional additional templates for this call only
 */
export function extractWithTemplate(
  ocrText: string,
  documentType: string,
  language: string,
  customTemplates?: DocumentTemplate[],
): TemplateResult {
  // Merge: call-specific custom → registered custom → built-in
  const allTemplates = customTemplates
    ? [...customTemplates, ...getAllTemplates()]
    : getAllTemplates();

  // Resolve document type
  const effectiveType =
    documentType === 'auto'
      ? detectDocumentType(ocrText, allTemplates)
      : documentType;

  // Find matching template (first match wins — custom templates checked first)
  const template = allTemplates.find(t => t.name === effectiveType);

  if (!template) {
    // Fall back to generic template
    const generic = allTemplates.find(t => t.name === 'generic');
    if (generic) {
      return extractWithEngine(ocrText, generic);
    }
    // Absolute fallback
    const lines = ocrText
      .split('\n')
      .map(l => l.trim())
      .filter(l => l.length > 0);
    return {
      documentType: effectiveType,
      data: JSON.stringify({ _documentType: effectiveType, content: { lines } }),
      confidence: 0.2,
    };
  }

  return extractWithEngine(ocrText, template);
}
