import type { HybridObject } from 'react-native-nitro-modules';

export interface PharmaScanner
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  ping(): string;
  getVersion(): string;
}
