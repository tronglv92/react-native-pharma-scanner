/**
 * Section boundary resolution.
 * Ported from TemplateExtractor.swift findLineIndex (line 489).
 */

import { normVi } from './text-utils';
import type { SectionDef } from './types';

/**
 * Find the first line index where any keyword matches (diacritic-insensitive).
 */
export function findLineIndex(
  lines: string[],
  keywords: string[],
): number | null {
  for (let i = 0; i < lines.length; i++) {
    const norm = normVi(lines[i]);
    if (keywords.some(kw => norm.includes(kw))) {
      return i;
    }
  }
  return null;
}

export interface SectionBounds {
  start: number;
  end: number;
}

/**
 * Resolve start/end boundaries for a named section given the full lines array
 * and all section definitions (needed for `endBefore` resolution).
 */
export function resolveSectionBounds(
  sectionDef: SectionDef,
  allSections: Record<string, SectionDef>,
  lines: string[],
): SectionBounds {
  // Resolve start
  let start = 0;
  if (sectionDef.startAt === 'document_start') {
    start = 0;
  } else if (sectionDef.startKeywords && sectionDef.startKeywords.length > 0) {
    const idx = findLineIndex(lines, sectionDef.startKeywords);
    start = idx ?? 0;
  }

  // Resolve end
  let end = lines.length;
  if (sectionDef.endAt === 'document_end') {
    end = lines.length;
  } else if (sectionDef.endBefore && sectionDef.endBefore.length > 0) {
    // endBefore references other section names — find the earliest start of any
    let earliest = lines.length;
    for (const refName of sectionDef.endBefore) {
      const refDef = allSections[refName];
      if (refDef) {
        if (refDef.startKeywords && refDef.startKeywords.length > 0) {
          const idx = findLineIndex(lines, refDef.startKeywords);
          if (idx !== null && idx < earliest) {
            earliest = idx;
          }
        }
      }
    }
    end = earliest;
  }

  return { start, end };
}
