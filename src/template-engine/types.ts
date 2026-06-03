// Template schema types — mirrors a YAML-like structure for document extraction templates

export interface FieldStrategy {
  method:
    | 'keyword_label'
    | 'keyword_contains'
    | 'regex'
    | 'regex_first_match'
    | 'vietnamese_date'
    | 'us_date';
  keywords?: string[];
  excludeKeywords?: string[];
  extract?:
    | 'value_after_colon'
    | 'tax_code'
    | 'company_name'
    | 'largest_number'
    | 'regex'
    | 'address_street'
    | 'address_city'
    | 'address_state'
    | 'address_zip';
  pattern?: string;
  checkNextLine?: boolean;
  scope?: 'full_text';
}

export interface FieldDef {
  type: 'string' | 'number';
  default: string | number;
  strategies: FieldStrategy[];
}

export interface SectionDef {
  startAt?: 'document_start';
  startKeywords?: string[];
  endAt?: 'document_end';
  endBefore?: string[];
  fields: Record<string, FieldDef>;
  // Item sections
  skipHeaderKeywords?: string[];
  itemSchema?: Record<string, FieldDef>;
  numericFields?: string[];
  fallbackNumericFields?: string[];
  /** Merge section fields into the root object instead of nesting under section name */
  flatten?: boolean;
  /** Number format: 'vi' (dot=thousands, comma=decimal) or 'en' (comma=thousands, dot=decimal) */
  numberFormat?: 'vi' | 'en';
}

export interface ConfidenceFieldRef {
  path: string; // dot-separated, e.g. "seller.companyName"
  type: 'non_empty' | 'non_zero';
}

export interface DocumentTemplate {
  name: string;
  version: number;
  detection: { keywords: string[] };
  sections: Record<string, SectionDef>;
  confidence: { maxScore: number; fields: ConfidenceFieldRef[] };
}

export interface TemplateResult {
  documentType: string;
  data: string; // JSON string
  confidence: number;
}
