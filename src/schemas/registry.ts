import type { DocumentSchema } from './types';
import { BUILT_IN_SCHEMAS } from './built-in';

// Internal registry keyed by schema key
const registry = new Map<string, DocumentSchema>();

// Seed with built-in schemas
for (const schema of BUILT_IN_SCHEMAS) {
  registry.set(schema.key, schema);
}

/**
 * Register a custom document schema.
 * Overwrites any existing schema with the same key.
 */
export function registerSchema(schema: DocumentSchema): void {
  registry.set(schema.key, schema);
}

/**
 * Register multiple document schemas at once.
 */
export function registerSchemas(schemas: DocumentSchema[]): void {
  for (const schema of schemas) {
    registry.set(schema.key, schema);
  }
}

/**
 * Retrieve a schema by key. Returns undefined if not found.
 */
export function getSchema(key: string): DocumentSchema | undefined {
  return registry.get(key);
}

/**
 * Return all registered schemas (built-in + custom).
 */
export function getAllSchemas(): DocumentSchema[] {
  return Array.from(registry.values());
}

/**
 * Remove a schema by key. Returns true if it existed.
 */
export function unregisterSchema(key: string): boolean {
  return registry.delete(key);
}

/**
 * Convert a DocumentSchema into an extraction prompt string.
 */
export function schemaToPrompt(schema: DocumentSchema): string {
  const structureJson = JSON.stringify(schema.structure, null, 2);
  let prompt = `Extract the following JSON structure from this ${schema.label.toLowerCase()}:\n${structureJson}`;
  if (schema.instruction) {
    prompt += `\n\n${schema.instruction}`;
  }
  return prompt;
}

/**
 * Generate the auto-detect prompt that includes all registered schemas.
 */
export function generateAutoDetectPrompt(): string {
  const schemas = getAllSchemas().filter(s => s.key !== 'auto');
  const validKeys = schemas.map(s => `"${s.key}"`).join(', ');

  let prompt = `Detect the document type and extract structured data.\n`;
  prompt += `You MUST set "_documentType" to exactly one of: ${validKeys}.\n`;
  prompt += `Always pick the most appropriate type based on the content. Never use "unknown" or any other value.\n\n`;
  prompt += `Use the corresponding JSON structure based on the detected type:\n`;

  for (const schema of schemas) {
    const structureWithType = { _documentType: schema.key, ...schema.structure };
    prompt += `\nFor ${schema.label.toLowerCase()}:\n`;
    prompt += JSON.stringify(structureWithType, null, 2);
    prompt += '\n';
  }

  return prompt;
}
