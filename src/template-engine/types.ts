// Template schema types — mirrors a YAML-like structure for document extraction templates

export interface FieldStrategy {
  method:
    | 'keyword_label'
    | 'keyword_contains'
    | 'regex'
    | 'regex_first_match'
    | 'vietnamese_date';
  keywords?: string[];
  excludeKeywords?: string[];
  extract?:
    | 'value_after_colon'
    | 'tax_code'
    | 'company_name'
    | 'largest_number'
    | 'regex';
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
