/**
 * Number parsing utilities for Vietnamese, standard (English), and European formats.
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
 * Parse a standard (English) formatted number string.
 * Uses `.` as decimal separator and `,` as thousands separator.
 * Examples: "1,394.67" → 1394.67, "689.70" → 689.70, "1000" → 1000
 */
export function parseStandardNumber(text: string): number {
  let cleaned = text.trim().replace(/[$%]/g, '').replace(/ /g, '');
  // Remove commas (thousands separators)
  cleaned = cleaned.replace(/,/g, '');
  return parseFloat(cleaned) || 0;
}

/**
 * Parse a European-formatted number string.
 * Uses `,` as decimal separator and space/`.` as thousands separator.
 * Examples: "689,70" → 689.70, "1 394,67" → 1394.67, "1.394,67" → 1394.67
 */
export function parseEuropeanNumber(text: string): number {
  const cleaned = text
    .trim()
    .replace(/[$%]/g, '')
    .replace(/ /g, '')   // remove thousands spaces
    .replace(/\./g, '')  // remove thousands dots
    .replace(',', '.');  // comma-decimal → dot-decimal
  return parseFloat(cleaned) || 0;
}

/**
 * Detect whether OCR text uses European number format.
 * Returns 'european' if comma-decimal patterns (e.g. 689,70) dominate,
 * 'standard' otherwise.
 */
export function detectNumberFormat(text: string): 'european' | 'standard' {
  // Match patterns like 689,70 or 1 394,67 (digits comma 2-digit decimal)
  const europeanMatches = text.match(/\d+,\d{2}(?!\d)/g) ?? [];
  // Match patterns like 689.70 or 1,394.67 (digits dot 2-digit decimal)
  const standardMatches = text.match(/\d+\.\d{2}(?!\d)/g) ?? [];

  return europeanMatches.length > standardMatches.length ? 'european' : 'standard';
}

/**
 * Format-aware number parser.
 */
export function parseNumberForFormat(text: string, format: 'european' | 'standard' | 'vi'): number {
  switch (format) {
    case 'european':
      return parseEuropeanNumber(text);
    case 'vi':
      return parseVietnameseNumber(text);
    default:
      return parseStandardNumber(text);
  }
}

/**
 * Find all number-like substrings in text and return the largest parsed value.
 * Uses Vietnamese number parser by default (backwards compatible).
 */
export function extractLargestNumber(text: string, format?: 'european' | 'standard' | 'vi'): number {
  if (format === 'european') {
    return extractLargestEuropeanNumber(text);
  }

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

/**
 * Find the largest European-format number in text.
 * Recognizes patterns like "1 394,67", "689,70", "1.394,67".
 */
export function extractLargestEuropeanNumber(text: string): number {
  // Match European numbers: optional thousands (space or dot separated) + comma + 2 decimals
  const regex = /(?:\d{1,3}(?:[\s.]\d{3})*,\d{2}|\d+,\d{2})/g;
  let largest = 0;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(text)) !== null) {
    const val = parseEuropeanNumber(match[0]);
    if (val > largest) {
      largest = val;
    }
  }
  // If no European matches found, fall back to standard extraction
  if (largest === 0) {
    const stdRegex = /[\d][\d.,]*[\d]/g;
    while ((match = stdRegex.exec(text)) !== null) {
      const val = parseStandardNumber(match[0]);
      if (val > largest) {
        largest = val;
      }
    }
  }
  return largest;
}
