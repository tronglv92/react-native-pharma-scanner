/**
 * Main template extraction engine.
 * Orchestrates: detect type → resolve sections → extract fields → compute confidence.
 */

import type { DocumentTemplate, SectionDef, FieldDef, FieldStrategy, TemplateResult } from './types';
import { normVi, matchesAny, isNumericLine } from './text-utils';
import { parseVietnameseNumber, extractLargestNumber } from './number-parser';
import {
  extractValueAfterColon,
  findTaxCode,
  extractCompanyName,
  extractDateFromVietnamese,
  extractPattern,
} from './field-extractors';
import { resolveSectionBounds } from './section-finder';
import { parseItems } from './item-parser';
import { computeConfidence } from './confidence';

/**
 * Auto-detect document type by scoring keyword matches across all templates.
 */
export function detectDocumentType(
  ocrText: string,
  templates: DocumentTemplate[],
): string {
  const lower = normVi(ocrText);
  let bestName = 'unknown';
  let bestScore = 0;

  for (const tpl of templates) {
    const score = tpl.detection.keywords.filter(kw => lower.includes(kw)).length;
    if (score > bestScore) {
      bestScore = score;
      bestName = tpl.name;
    }
  }

  return bestScore > 0 ? bestName : 'unknown';
}

/**
 * Extract fields from OCR text using a specific template.
 */
export function extractWithEngine(
  ocrText: string,
  template: DocumentTemplate,
): TemplateResult {
  const lines = ocrText
    .split('\n')
    .map(l => l.trim());

  const data: Record<string, unknown> = {};

  for (const [sectionName, sectionDef] of Object.entries(template.sections)) {
    const bounds = resolveSectionBounds(sectionDef, template.sections, lines);

    if (sectionDef.itemSchema) {
      // Item section — parse table items
      data[sectionName] = parseItems(lines, bounds.start, bounds.end, sectionDef);
    } else {
      // Regular section — extract fields
      const sectionData: Record<string, string | number> = {};

      for (const [fieldName, fieldDef] of Object.entries(sectionDef.fields)) {
        sectionData[fieldName] = extractField(
          fieldDef,
          lines,
          bounds.start,
          bounds.end,
          ocrText,
        );
      }

      data[sectionName] = sectionData;
    }
  }

  // Totals fallback: if we have a "totals" section with mostly zeros,
  // try sequential number extraction
  applyTotalsFallback(data, lines, template);

  const confidence = computeConfidence(template, data);

  return {
    documentType: template.name,
    data: JSON.stringify(data),
    confidence,
  };
}

/**
 * Extract a single field using its strategies in order.
 */
function extractField(
  fieldDef: FieldDef,
  lines: string[],
  sectionStart: number,
  sectionEnd: number,
  fullText: string,
): string | number {
  for (const strategy of fieldDef.strategies) {
    const result = applyStrategy(
      strategy,
      fieldDef,
      lines,
      sectionStart,
      sectionEnd,
      fullText,
    );
    if (result !== null && result !== '' && result !== 0) {
      return result;
    }
  }
  return fieldDef.default;
}

/**
 * Apply a single extraction strategy.
 */
function applyStrategy(
  strategy: FieldStrategy,
  fieldDef: FieldDef,
  lines: string[],
  sectionStart: number,
  sectionEnd: number,
  fullText: string,
): string | number | null {
  const searchLines = strategy.scope === 'full_text'
    ? lines
    : lines.slice(sectionStart, sectionEnd);
  const searchOffset = strategy.scope === 'full_text' ? 0 : sectionStart;

  switch (strategy.method) {
    case 'keyword_label': {
      const keywords = strategy.keywords ?? [];
      const excludeKw = strategy.excludeKeywords ?? [];
      for (let i = 0; i < searchLines.length; i++) {
        const norm = normVi(searchLines[i]);
        if (!matchesAny(norm, keywords)) continue;
        if (excludeKw.length > 0 && matchesAny(norm, excludeKw)) continue;

        const globalIdx = i + searchOffset;

        switch (strategy.extract) {
          case 'value_after_colon':
            return extractValueAfterColon(searchLines[i], lines, globalIdx);
          case 'tax_code':
            return findTaxCode(searchLines[i], lines, globalIdx);
          case 'company_name':
            return extractCompanyName(searchLines[i], lines, globalIdx);
          case 'largest_number': {
            let num = extractLargestNumber(searchLines[i]);
            if (num > 0) return num;
            // Check next line
            if (strategy.checkNextLine !== false && i + 1 < searchLines.length) {
              num = extractLargestNumber(searchLines[i + 1]);
              if (num > 0) return num;
            }
            return null;
          }
          case 'regex': {
            if (!strategy.pattern) return null;
            const m = extractPattern(searchLines[i], strategy.pattern);
            if (m) return fieldDef.type === 'number' ? parseVietnameseNumber(m) : m;
            // Check next line
            if (strategy.checkNextLine && i + 1 < searchLines.length) {
              const m2 = extractPattern(searchLines[i + 1], strategy.pattern);
              if (m2) return fieldDef.type === 'number' ? parseVietnameseNumber(m2) : m2;
            }
            return null;
          }
          default:
            return extractValueAfterColon(searchLines[i], lines, globalIdx);
        }
      }
      return null;
    }

    case 'keyword_contains': {
      // Like keyword_label but checks if any keyword is contained in the line
      // Used for fields like VAT rate that need % extraction
      const keywords = strategy.keywords ?? [];
      for (let i = 0; i < searchLines.length; i++) {
        const norm = normVi(searchLines[i]);
        if (!matchesAny(norm, keywords)) continue;

        if (strategy.pattern) {
          const m = extractPattern(searchLines[i], strategy.pattern);
          if (m) return fieldDef.type === 'number' ? parseFloat(m) : m;
          // Also try on normalized
          const m2 = extractPattern(norm, strategy.pattern);
          if (m2) return fieldDef.type === 'number' ? parseFloat(m2) : m2;
        }
      }
      return null;
    }

    case 'regex': {
      if (!strategy.pattern) return null;
      const text = strategy.scope === 'full_text' ? fullText : searchLines.join('\n');
      const m = extractPattern(text, strategy.pattern);
      if (m) return fieldDef.type === 'number' ? parseVietnameseNumber(m) : m;
      return null;
    }

    case 'regex_first_match': {
      if (!strategy.pattern) return null;
      const text = strategy.scope === 'full_text' ? fullText : searchLines.join('\n');
      const m = extractPattern(text, strategy.pattern);
      if (m) return fieldDef.type === 'number' ? parseVietnameseNumber(m) : m;
      return null;
    }

    case 'vietnamese_date': {
      const text = strategy.scope === 'full_text' ? fullText : searchLines.join('\n');
      return extractDateFromVietnamese(text);
    }

    default:
      return null;
  }
}

/**
 * If totals section has zeros, try sequential number extraction.
 * Pattern: collect standalone numeric lines after the totals section start,
 * assign them to subtotal, vatAmount, totalPayment.
 */
function applyTotalsFallback(
  data: Record<string, unknown>,
  lines: string[],
  template: DocumentTemplate,
): void {
  const totalsDef = template.sections['totals'];
  if (!totalsDef) return;

  const totals = data['totals'] as Record<string, string | number> | undefined;
  if (!totals) return;

  const fallbackFields = totalsDef.fallbackNumericFields ?? [
    'subtotal',
    'vatAmount',
    'totalPayment',
  ];

  // Check if any fallback field is still at zero
  const hasZero = fallbackFields.some(f => totals[f] === 0);
  if (!hasZero) return;

  // Find the totals section start
  const bounds = resolveSectionBounds(totalsDef, template.sections, lines);

  // Collect standalone numeric lines
  const numbers: number[] = [];
  for (let i = bounds.start; i < lines.length; i++) {
    const line = lines[i].trim();
    if (isNumericLine(line)) {
      numbers.push(parseVietnameseNumber(line));
    }
  }

  // Assign in order to fields that are still zero
  if (numbers.length >= fallbackFields.length) {
    for (let i = 0; i < fallbackFields.length; i++) {
      if (totals[fallbackFields[i]] === 0) {
        totals[fallbackFields[i]] = numbers[i];
      }
    }
  }
}
