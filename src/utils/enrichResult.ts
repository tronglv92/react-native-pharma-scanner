import { parseDocumentData } from '../document-types';
import type { DocumentExtractionResult } from '../specs/types.nitro';
import { validateDocumentData } from './validation';
import type { ValidationIssue } from './validation';

export function enrichExtractionResult(
  result: DocumentExtractionResult,
): DocumentExtractionResult & { validationIssues: ValidationIssue[] } {
  const parsed = parseDocumentData(result.data);
  if (!parsed) {
    return { ...result, validationIssues: [] };
  }

  const validation = validateDocumentData(result.documentType, parsed);
  const validationWarnings = validation.issues.map(
    issue =>
      `VALIDATION:${issue.severity.toUpperCase()}:${issue.code} - ${issue.message}`,
  );

  return {
    ...result,
    warnings: [...result.warnings, ...validationWarnings],
    validationIssues: validation.issues,
  };
}
