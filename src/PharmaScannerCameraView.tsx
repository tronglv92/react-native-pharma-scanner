import { requireNativeComponent, type ViewProps } from 'react-native';

export interface PharmaScannerCameraViewProps extends ViewProps {
  overlayColor?: string;
  overlayLineWidth?: number;
  overlayFillColor?: string;
  showOverlay?: boolean;
}

const NativeView =
  requireNativeComponent<PharmaScannerCameraViewProps>('PharmaScannerCameraView');

export function PharmaScannerCameraView(props: PharmaScannerCameraViewProps) {
  return <NativeView {...props} />;
}
