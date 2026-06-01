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
 * 2. Collect non-empty lines until section end
 * 3. Separate product name (non-numeric start) from data lines
 * 4. Extract dates, lot numbers, units from short lines
 * 5. Assign last N numeric values to `numericFields`
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

  // Build a single item (same logic as Swift — single item block)
  const item: ParsedItem = {
    stt: 1,
    productName: '',
    lotNumber: '',
    expiryDate: '',
    unit: '',
  };
  // Initialize numeric fields
  for (const f of numericFields) {
    item[f] = 0;
  }

  // Collect product name from non-numeric lines at the start
  const productNameParts: string[] = [];
  let numericStartIdx = 0;

  for (let idx = 0; idx < itemLines.length; idx++) {
    const trimmed = itemLines[idx].trim();
    // If line starts with a digit or is purely numeric, stop collecting name
    if (/^\d/.test(trimmed) || isNumericLine(trimmed)) {
      numericStartIdx = idx;
      break;
    }
    // Check for STT prefix like "1  Product Name"
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

  // Extract values from remaining lines
  const numericValues: string[] = [];
  for (let idx = numericStartIdx; idx < itemLines.length; idx++) {
    const line = itemLines[idx];
    // Date detection
    if (/\d{2}\/\d{2}\/\d{4}/.test(line)) {
      item.expiryDate = line.trim();
    } else if (isNumericLine(line)) {
      numericValues.push(line.trim());
    } else if (line.length <= 10 && !line.includes(' ')) {
      // Short non-numeric: lot number or unit
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

  // Assign numeric values to fields (last N values)
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

  return [item];
}
