/**
 * Table item line parsing.
 * Ported from TemplateExtractor.swift extractInvoice lines 174-273.
 */

import { normVi, matchesAny, isNumericLine } from './text-utils';
import { parseVietnameseNumber } from './number-parser';
import { extractPattern } from './field-extractors';
import type { SectionDef } from './types';

export interface ParsedItem {
  [key: string]: string | number;
}

/**
 * Parse item lines from a section that has `itemSchema`.
 *
 * Logic:
 * 1. Skip header lines matching `skipHeaderKeywords`
 * 2. Find item boundaries using STT pattern (lines starting with "N." e.g. "1.", "2.")
 * 3. For each item block: collect product name lines + numeric values
 * 4. Assign trailing numeric values to `numericFields` from right to left
 * 5. Return array of all parsed items
 */
export function parseItems(
  lines: string[],
  sectionStart: number,
  sectionEnd: number,
  sectionDef: SectionDef,
): ParsedItem[] {
  const skipKw = sectionDef.skipHeaderKeywords ?? [];
  const numericFields = sectionDef.numericFields ?? [
    'quantity',
    'unitPrice',
    'amount',
  ];

  // Skip header lines
  let dataStart = sectionStart + 1;
  while (dataStart < sectionEnd) {
    const norm = normVi(lines[dataStart]);
    if (matchesAny(norm, skipKw)) {
      dataStart++;
    } else {
      break;
    }
  }

  // Collect non-empty item lines
  const itemLines: string[] = [];
  for (let i = dataStart; i < sectionEnd; i++) {
    const line = lines[i].trim();
    if (line.length > 0) {
      itemLines.push(line);
    }
  }

  if (itemLines.length === 0) return [];

  // Find item boundaries: lines starting with "N." pattern (e.g. "1.", "2.", "10.")
  const sttPattern = /^(\d+)\.\s/;
  const boundaries: number[] = [];
  for (let i = 0; i < itemLines.length; i++) {
    if (sttPattern.test(itemLines[i])) {
      boundaries.push(i);
    }
  }

  // If no STT boundaries found, fall back to single-item parsing
  if (boundaries.length === 0) {
    return [parseSingleItem(itemLines, numericFields)];
  }

  // Parse each item block
  const items: ParsedItem[] = [];
  for (let b = 0; b < boundaries.length; b++) {
    const blockStart = boundaries[b];
    const blockEnd = b + 1 < boundaries.length ? boundaries[b + 1] : itemLines.length;
    const blockLines = itemLines.slice(blockStart, blockEnd);

    const item = parseItemBlock(blockLines, numericFields);
    items.push(item);
  }

  return items;
}

/**
 * Parse a single item block (lines belonging to one STT item).
 * First line starts with "N. ..." containing the STT and possibly the product name + numbers.
 * Subsequent lines may be product name continuations, units, or numeric values.
 */
function parseItemBlock(blockLines: string[], numericFields: string[]): ParsedItem {
  const sttMatch = blockLines[0].match(/^(\d+)\.\s+(.*)/);
  const stt = sttMatch ? parseInt(sttMatch[1], 10) : 1;
  const firstLineRest = sttMatch ? sttMatch[2] : blockLines[0];

  const item: ParsedItem = { stt, productName: '', unit: '' };
  for (const f of numericFields) {
    item[f] = 0;
  }

  // Collect all content: first line remainder + subsequent lines
  const allParts: string[] = [firstLineRest.trim()];
  for (let i = 1; i < blockLines.length; i++) {
    allParts.push(blockLines[i].trim());
  }

  // Separate into product name parts and numeric/unit parts
  const productNameParts: string[] = [];
  const numericValues: string[] = [];
  let unit = '';

  for (const part of allParts) {
    if (isNumericLine(part)) {
      numericValues.push(part);
    } else if (isShortUnit(part)) {
      unit = part;
    } else {
      // Could be a mixed line (product name + trailing numbers) or pure text
      const { textPart, numbers, unitFound } = splitTextAndNumbers(part);
      if (textPart.length > 0) {
        productNameParts.push(textPart);
      }
      if (unitFound) {
        unit = unitFound;
      }
      for (const n of numbers) {
        numericValues.push(n);
      }
    }
  }

  item.productName = productNameParts.join(' ').trim();
  if (unit) {
    item.unit = unit;
  }

  // Assign numeric values to fields (last N values mapped right-to-left)
  const parsedNumbers = numericValues.map(v => parseVietnameseNumber(v));
  if (parsedNumbers.length >= numericFields.length) {
    const offset = parsedNumbers.length - numericFields.length;
    for (let i = 0; i < numericFields.length; i++) {
      item[numericFields[i]] = parsedNumbers[offset + i];
    }
  } else if (parsedNumbers.length > 0) {
    // Assign from the end
    const offset = numericFields.length - parsedNumbers.length;
    for (let i = 0; i < parsedNumbers.length; i++) {
      item[numericFields[offset + i]] = parsedNumbers[i];
    }
  }

  return item;
}

/**
 * Check if a string is a short unit keyword (e.g. "each", "hop", "chai").
 */
function isShortUnit(text: string): boolean {
  const trimmed = text.trim().toLowerCase();
  if (trimmed.length > 10 || trimmed.includes(' ')) return false;
  const unitKeywords = [
    'each', 'pcs', 'pc', 'kg', 'g', 'l', 'ml', 'box', 'set',
    'hop', 'chai', 'lo', 'ong', 'vi', 'goi', 'tuyp', 'tube',
    'cai', 'vien', 'cap', 'doi', 'cuon', 'quyen',
  ];
  return unitKeywords.includes(trimmed) || /^[a-zA-Z]{1,6}$/.test(trimmed) && !/\d/.test(trimmed);
}

/**
 * Split a mixed text line into its text portion and trailing numeric tokens.
 * E.g. "Product Name 3,00 each 209,00 627,00 10% 689,70"
 *   → textPart="Product Name", numbers=["3,00","209,00","627,00","10","689,70"], unit="each"
 */
function splitTextAndNumbers(line: string): { textPart: string; numbers: string[]; unitFound: string } {
  const tokens = line.split(/\s+/);
  let unitFound = '';
  const numbers: string[] = [];

  // Scan from end to find trailing numeric tokens
  let textEnd = tokens.length;
  for (let i = tokens.length - 1; i >= 0; i--) {
    const tok = tokens[i];
    if (isNumericToken(tok)) {
      // Strip $ and % for the numeric value but keep the raw token for parsing
      numbers.unshift(tok.replace(/[$%]/g, ''));
      textEnd = i;
    } else if (isShortUnit(tok)) {
      unitFound = tok.trim().toLowerCase();
      textEnd = i;
    } else {
      break;
    }
  }

  const textPart = tokens.slice(0, textEnd).join(' ');
  return { textPart, numbers, unitFound };
}

/**
 * Check if a token looks numeric (possibly with $, %, comma, dot, spaces).
 */
function isNumericToken(token: string): boolean {
  const cleaned = token.replace(/[$%.,\s]/g, '');
  return cleaned.length > 0 && /^\d+$/.test(cleaned);
}

/**
 * Fallback: parse all lines as a single item (original behavior).
 */
function parseSingleItem(itemLines: string[], numericFields: string[]): ParsedItem {
  const item: ParsedItem = {
    stt: 1,
    productName: '',
    lotNumber: '',
    expiryDate: '',
    unit: '',
  };
  for (const f of numericFields) {
    item[f] = 0;
  }

  const productNameParts: string[] = [];
  let numericStartIdx = 0;

  for (let idx = 0; idx < itemLines.length; idx++) {
    const trimmed = itemLines[idx].trim();
    if (/^\d/.test(trimmed) || isNumericLine(trimmed)) {
      numericStartIdx = idx;
      break;
    }
    const sttMatch = extractPattern(trimmed, '^(\\d+)\\s+(.+)');
    if (sttMatch && sttMatch.length <= 3) {
      const rest = extractPattern(trimmed, '^\\d+\\s+(.+)');
      if (rest) productNameParts.push(rest);
    } else {
      productNameParts.push(trimmed);
    }
    numericStartIdx = idx + 1;
  }
  item.productName = productNameParts.join(' ');

  const numericValues: string[] = [];
  for (let idx = numericStartIdx; idx < itemLines.length; idx++) {
    const line = itemLines[idx];
    if (/\d{2}\/\d{2}\/\d{4}/.test(line)) {
      item.expiryDate = line.trim();
    } else if (isNumericLine(line)) {
      numericValues.push(line.trim());
    } else if (line.length <= 10 && !line.includes(' ')) {
      const hasDigits = /\d/.test(line);
      if (hasDigits && item.lotNumber === '') {
        item.lotNumber = line;
      } else if (!hasDigits && item.unit === '') {
        item.unit = line;
      } else if (item.lotNumber === '') {
        item.lotNumber = line;
      }
    }
  }

  const parsedNumbers = numericValues.map(v => parseVietnameseNumber(v));
  if (parsedNumbers.length >= numericFields.length) {
    const offset = parsedNumbers.length - numericFields.length;
    for (let i = 0; i < numericFields.length; i++) {
      item[numericFields[i]] = parsedNumbers[offset + i];
    }
  } else if (parsedNumbers.length === 2 && numericFields.length >= 2) {
    item[numericFields[numericFields.length - 2]] = parsedNumbers[0];
    item[numericFields[numericFields.length - 1]] = parsedNumbers[1];
  } else if (parsedNumbers.length === 1 && numericFields.length >= 1) {
    item[numericFields[numericFields.length - 1]] = parsedNumbers[0];
  }

  return item;
}
