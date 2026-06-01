import yaml from 'js-yaml';
import type { DocumentTemplate } from '../template-engine/types';

// Import YAML files as raw strings (via Metro yaml-transformer)
import invoiceYaml from './invoice.yaml';
import prescriptionYaml from './prescription.yaml';
import receiptYaml from './receipt.yaml';
import genericYaml from './generic.yaml';

function parseTemplate(raw: string): DocumentTemplate {
  return yaml.load(raw) as DocumentTemplate;
}

/**
 * Built-in templates parsed from YAML, ordered by specificity.
 */
export const builtinTemplates: DocumentTemplate[] = [
  parseTemplate(invoiceYaml),
  parseTemplate(prescriptionYaml),
  parseTemplate(receiptYaml),
  parseTemplate(genericYaml),
];

/**
 * Registry for user-provided custom templates.
 * Users of the library can call `registerTemplate()` to add their own YAML templates
 * at runtime, and the engine will automatically include them during extraction.
 */
const customTemplateRegistry: DocumentTemplate[] = [];

/**
 * Register a custom template from a YAML string.
 * The template will be used in auto-detection and extraction alongside built-in ones.
 *
 * @example
 * ```ts
 * import { registerTemplate } from 'react-native-pharma-scanner';
 * import myTemplateYaml from './my-custom-template.yaml';
 * registerTemplate(myTemplateYaml);
 * ```
 */
export function registerTemplate(yamlString: string): DocumentTemplate {
  const template = parseTemplate(yamlString);
  // Replace existing template with the same name, or add new
  const existingIdx = customTemplateRegistry.findIndex(t => t.name === template.name);
  if (existingIdx >= 0) {
    customTemplateRegistry[existingIdx] = template;
  } else {
    customTemplateRegistry.push(template);
  }
  return template;
}

/**
 * Register a custom template from a pre-parsed object.
 */
export function registerTemplateObject(template: DocumentTemplate): void {
  const existingIdx = customTemplateRegistry.findIndex(t => t.name === template.name);
  if (existingIdx >= 0) {
    customTemplateRegistry[existingIdx] = template;
  } else {
    customTemplateRegistry.push(template);
  }
}

/**
 * Remove a registered custom template by name.
 */
export function unregisterTemplate(name: string): boolean {
  const idx = customTemplateRegistry.findIndex(t => t.name === name);
  if (idx >= 0) {
    customTemplateRegistry.splice(idx, 1);
    return true;
  }
  return false;
}

/**
 * Get all registered custom templates.
 */
export function getCustomTemplates(): readonly DocumentTemplate[] {
  return customTemplateRegistry;
}

/**
 * Get all available templates (built-in + custom).
 * Custom templates are checked first, allowing users to override built-in ones.
 */
export function getAllTemplates(): DocumentTemplate[] {
  return [...customTemplateRegistry, ...builtinTemplates];
}
