declare module 'react-native-config' {
  export interface NativeConfig {
    API_KEY?: string;
    BASE_URL?: string;
  }

  declare const Config: NativeConfig;
  export default Config;
}
