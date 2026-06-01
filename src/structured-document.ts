import type {
  StructuredDocumentResult,
  KeyValuePair,
} from './specs/types.nitro';

export interface OrganizedDocument {
  type: string;
  header: KeyValuePair[];
  body: KeyValuePair[];
  footer: KeyValuePair[];
  tables: string[][][];
  entities: {
    dates: string[];
    moneyAmounts: string[];
    phones: string[];
    emails: string[];
  };
  barcodes: string[];
  rawText: string;
  confidence: number;
}

/**
 * Organizes a StructuredDocumentResult into a more consumable format.
 * Groups key-value pairs by paragraph position, flattens tables,
 * and categorizes entities by type.
 */
export function organizeDocument(
  result: StructuredDocumentResult,
): OrganizedDocument {
  // Build position-to-paragraphs map
  const topTexts = new Set<string>();
  const bottomTexts = new Set<string>();

  for (const p of result.paragraphs) {
    if (p.position === 'top') {
      topTexts.add(p.text);
    } else if (p.position === 'bottom') {
      bottomTexts.add(p.text);
    }
  }

  // Classify key-value pairs by which paragraph position they came from
  const header: KeyValuePair[] = [];
  const body: KeyValuePair[] = [];
  const footer: KeyValuePair[] = [];

  for (const kv of result.summary.keyValuePairs) {
    // Check if this KV pair's key appears in a top/bottom paragraph
    const fullLine = `${kv.key}: ${kv.value}`;
    if ([...topTexts].some(t => t.includes(kv.key))) {
      header.push(kv);
    } else if ([...bottomTexts].some(t => t.includes(kv.key))) {
      footer.push(kv);
    } else {
      body.push(kv);
    }
  }

  // Flatten TableRow[] to string[][]
  const tables: string[][][] = result.tables.map(table =>
    table.rows.map(row => row.cells),
  );

  // Categorize entities by type
  const dates: string[] = [];
  const moneyAmounts: string[] = [];
  const phones: string[] = [];
  const emails: string[] = [];

  for (const entity of result.detectedEntities) {
    switch (entity.type) {
      case 'date':
        dates.push(entity.value);
        break;
      case 'money':
        moneyAmounts.push(entity.value);
        break;
      case 'phone':
        phones.push(entity.value);
        break;
      case 'email':
        emails.push(entity.value);
        break;
    }
  }

  return {
    type: result.documentType,
    header,
    body,
    footer,
    tables,
    entities: { dates, moneyAmounts, phones, emails },
    barcodes: result.barcodes,
    rawText: result.rawText,
    confidence: result.confidence,
  };
}
