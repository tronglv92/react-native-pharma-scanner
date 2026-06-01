/**
 * Field extraction strategies.
 * Ported from TemplateExtractor.swift lines 501-648.
 */

import { normVi, matchesAny } from './text-utils';

// Keywords that indicate a label line — used to avoid grabbing the next line
// when it's actually another label.
const LABEL_KEYWORDS = [
  'ma so', 'so thue', 'tax', 'dia chi', 'address', 'dien thoai', 'tel',
  'nguoi', 'buyer', 'seller', 'ten don vi', 'hinh thuc', 'can cuoc',
  'ky hieu', 'serial', 'company', 'client',
];

/**
 * Extract text after `:` or `)` on the same line, or fall back to next line.
 */
export function extractValueAfterColon(
  line: string,
  lines: string[],
  index: number,
): string {
  // Try after last colon
  const colonIdx = line.lastIndexOf(':');
  if (colonIdx >= 0) {
    const after = line.slice(colonIdx + 1).trim();
    if (after.length > 0) return after;
  }
  // Try after last )
  const parenIdx = line.lastIndexOf(')');
  if (parenIdx >= 0) {
    const after = line
      .slice(parenIdx + 1)
      .replace(/^[:\s;]+/, '')
      .trim();
    if (after.length > 0) return after;
  }
  // Try after ;
  const semiIdx = line.lastIndexOf(';');
  if (semiIdx >= 0) {
    const after = line.slice(semiIdx + 1).trim();
    if (after.length > 0) return after;
  }
  // Fall back to next line if current is just a label
  if (index + 1 < lines.length) {
    const nextLine = lines[index + 1].trim();
    if (nextLine.length > 0) {
      const nextNorm = normVi(nextLine);
      if (!matchesAny(nextNorm, LABEL_KEYWORDS)) {
        return nextLine;
      }
    }
  }
  return '';
}

/**
 * Find a tax code (10-14 digit number) on the current or next line.
 */
export function findTaxCode(
  line: string,
  lines: string[],
  index: number,
): string {
  const taxRe = /(\d{10,14})/;
  const m = line.match(taxRe);
  if (m) return m[1];
  if (index + 1 < lines.length) {
    const m2 = lines[index + 1].match(taxRe);
    if (m2) return m2[1];
  }
  return '';
}

/**
 * Extract a company name starting with "CONG TY" (diacritic-insensitive).
 * Appends continuation from the next line if the name is short.
 */
export function extractCompanyName(
  line: string,
  lines: string[],
  index: number,
): string {
  const norm = normVi(line);
  const ctIdx = norm.indexOf('cong ty');
  if (ctIdx < 0) {
    // Also check for "cty"
    const ctyIdx = norm.indexOf('cty');
    if (ctyIdx >= 0) {
      let name = line.slice(ctyIdx).trim();
      if (name.length < 30 && index + 1 < lines.length) {
        const nextNorm = normVi(lines[index + 1]);
        if (
          !matchesAny(nextNorm, LABEL_KEYWORDS) &&
          !lines[index + 1].trim().startsWith('(')
        ) {
          name = name + ' ' + lines[index + 1].trim();
        }
      }
      return name;
    }
    return line;
  }

  // Map from normalized index back to original string.
  // Since normVi can change character count, find the position heuristically.
  let name = line.slice(ctIdx).trim();

  // If short, check next line for continuation
  if (name.length < 30 && index + 1 < lines.length) {
    const nextNorm = normVi(lines[index + 1]);
    if (
      !matchesAny(nextNorm, LABEL_KEYWORDS) &&
      !lines[index + 1].trim().startsWith('(')
    ) {
      name = name + ' ' + lines[index + 1].trim();
    }
  }
  return name;
}

/**
 * Extract a Vietnamese-style date: "ngay DD thang MM nam YYYY".
 * Handles common OCR garbling (nedy, ngdy, etc.).
 */
export function extractDateFromVietnamese(text: string): string | null {
  const norm = normVi(text);
  const re =
    /(?:ngay|nedy|ngdy).*?(\d{1,2}).*?(?:thang).*?(\d{1,2}).*?(?:nam|name).*?(\d{4})/i;
  const m = norm.match(re);
  if (m) {
    return `${m[1]}/${m[2]}/${m[3]}`;
  }
  return null;
}

/**
 * Extract first match of a regex pattern with an optional capture group.
 */
export function extractPattern(text: string, pattern: string): string | null {
  try {
    const re = new RegExp(pattern, 'i');
    const m = text.match(re);
    if (!m) return null;
    // Return capture group 1 if present, otherwise full match
    return m[1] !== undefined ? m[1] : m[0];
  } catch {
    return null;
  }
}
