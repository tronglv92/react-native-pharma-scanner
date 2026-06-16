/**
 * A document schema describes the expected JSON structure for a document type.
 * Users can register custom schemas to extract new document types.
 */
export interface DocumentSchema {
  /** Unique key identifying this document type (e.g. 'invoice', 'lab_report'). */
  key: string;
  /** Human-readable label (e.g. 'Invoice'). */
  label: string;
  /** Short description of the document type. */
  description: string;
  /** JSON structure template — values are placeholders (empty strings, 0, empty arrays). */
  structure: Record<string, unknown>;
  /** Optional extra instruction appended to the extraction prompt. */
  instruction?: string;
}
