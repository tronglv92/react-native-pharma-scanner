import { requireNativeComponent, type ViewProps } from 'react-native';

const NativeView = requireNativeComponent<ViewProps>('PharmaScannerCameraView');

export function PharmaScannerCameraView(props: ViewProps) {
  return <NativeView {...props} />;
}
