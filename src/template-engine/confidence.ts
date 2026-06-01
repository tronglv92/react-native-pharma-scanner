/**
 * Confidence score computation.
 * Ported from TemplateExtractor.swift computeInvoiceConfidence (line 662).
 */

import type { ConfidenceFieldRef, DocumentTemplate } from './types';

/**
 * Walk the confidence field refs, check each dot-path against the extracted data,
 * and compute score = (matched / total) * maxScore.
 */
export function computeConfidence(
  template: DocumentTemplate,
  data: Record<string, unknown>,
): number {
  const { maxScore, fields } = template.confidence;
  if (fields.length === 0) return maxScore;

  let matched = 0;

  for (const ref of fields) {
    const value = getNestedValue(data, ref.path);
    if (ref.type === 'non_empty') {
      if (typeof value === 'string' && value.length > 0) matched++;
      else if (Array.isArray(value) && value.length > 0) matched++;
      else if (value !== null && value !== undefined && value !== '')
        matched++;
    } else if (ref.type === 'non_zero') {
      if (typeof value === 'number' && value > 0) matched++;
    }
  }

  return (matched / fields.length) * maxScore;
}

function getNestedValue(
  obj: Record<string, unknown>,
  path: string,
): unknown {
  const parts = path.split('.');
  let current: unknown = obj;
  for (const part of parts) {
    if (current === null || current === undefined) return undefined;
    if (typeof current !== 'object') return undefined;
    current = (current as Record<string, unknown>)[part];
  }
  return current;
}
