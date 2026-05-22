export type FlashMode = 'auto' | 'on' | 'off';

export interface CapturedImage {
  uri: string;
  width: number;
  height: number;
  base64?: string;
}

export interface Point {
  x: number;
  y: number;
}

export interface Corners {
  topLeft: Point;
  topRight: Point;
  bottomLeft: Point;
  bottomRight: Point;
}

export interface DocumentDetection {
  detected: boolean;
  corners: Corners;
  confidence: number;
  isStable: boolean;
}
