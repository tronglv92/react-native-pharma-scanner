export type { DocumentSchema } from './types';
export { BUILT_IN_SCHEMAS } from './built-in';
export {
  registerSchema,
  registerSchemas,
  getSchema,
  getAllSchemas,
  unregisterSchema,
  schemaToPrompt,
  generateAutoDetectPrompt,
} from './registry';
