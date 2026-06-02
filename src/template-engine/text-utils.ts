/**
 * Text normalization and matching utilities.
 * Ported from TemplateExtractor.swift lines 483-605.
 */

/**
 * Normalize Vietnamese text: strip diacritics + lowercase.
 * Equivalent to Swift's `folding(options: [.diacriticInsensitive, .caseInsensitive])`.
 */
export function normVi(text: string): string {
  let result = text
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
  // Handle đ/Đ which NFD doesn't decompose
  result = result.replace(/đ/g, 'd').replace(/Đ/gi, 'd');
  return result;
}

/**
 * Check if `text` contains any of the given keywords.
 */
export function matchesAny(text: string, keywords: string[]): boolean {
  return keywords.some(kw => text.includes(kw));
}

/**
 * Check if a line is purely numeric (after stripping `.`, `,`, spaces).
 */
export function isNumericLine(text: string): boolean {
  const cleaned = text
    .trim()
    .replace(/[$%]/g, '')
    .replace(/\./g, '')
    .replace(/,/g, '')
    .replace(/ /g, '');
  return cleaned.length > 0 && /^\d+$/.test(cleaned);
}
