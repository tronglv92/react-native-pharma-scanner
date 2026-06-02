/**
 * Vietnamese number parsing utilities.
 * Ported from TemplateExtractor.swift lines 605-664.
 */

/**
 * Parse a Vietnamese-formatted number string.
 * Vietnamese uses `.` as thousands separator and `,` as decimal separator.
 * Examples: "286.000" → 286000, "272,00" → 272, "1.234.567" → 1234567
 */
export function parseVietnameseNumber(text: string): number {
  let cleaned = text.trim().replace(/[$%]/g, '').replace(/ /g, '');

  if (cleaned.includes(',')) {
    const parts = cleaned.split(',');
    if (parts.length === 2 && parts[1].length <= 2) {
      // Comma is decimal separator: 272,00 -> 272.00
      cleaned = cleaned.replace(/\./g, '').replace(',', '.');
    } else {
      // Comma as thousands separator
      cleaned = cleaned.replace(/,/g, '');
    }
  } else {
    // Dots as thousands: 286.000 -> 286000
    const dotParts = cleaned.split('.');
    if (
      dotParts.length > 1 &&
      dotParts.slice(1).every(p => p.length === 3 || p.length === 2)
    ) {
      cleaned = cleaned.replace(/\./g, '');
    }
  }

  return parseFloat(cleaned) || 0;
}

/**
 * Find all number-like substrings in text and return the largest parsed value.
 */
export function extractLargestNumber(text: string): number {
  const regex = /[\d][\d.,]*[\d]/g;
  let largest = 0;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(text)) !== null) {
    const val = parseVietnameseNumber(match[0]);
    if (val > largest) {
      largest = val;
    }
  }
  return largest;
}
