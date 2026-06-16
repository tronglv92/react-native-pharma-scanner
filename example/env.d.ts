declare module 'react-native-config' {
  export interface NativeConfig {
    MISTRAL_API_KEY?: string;
  }

  declare const Config: NativeConfig;
  export default Config;
}

declare module '*.yaml' {
  const content: string;
  export default content;
}

declare module '*.yml' {
  const content: string;
  export default content;
}
