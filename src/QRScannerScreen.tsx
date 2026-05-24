import React, { useEffect, useRef, useState, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Animated,
  Dimensions,
  TouchableOpacity,
  Vibration,
  Platform,
  Easing,
} from 'react-native';
import { PharmaScannerCameraView } from './PharmaScannerCameraView';
import type { BarcodeResult } from './specs/types.nitro';

const { width: SCREEN_W, height: SCREEN_H } = Dimensions.get('window');

// Layout
const SCAN_AREA_SIZE = 260;
const CORNER_LENGTH = 30;
const CORNER_THICKNESS = 4;
const CORNER_RADIUS = 2;
const SCAN_LINE_HEIGHT = 3;

// Animation timing
const ENTRANCE_DURATION = 300;
const PULSE_DURATION = 2000;
const SCAN_LINE_DURATION = 1400;
const DETECTION_DURATION = 200;
const POST_SCAN_DURATION = 300;

// Visual
const OVERLAY_OPACITY = 0.65;

const TOP_OFFSET = (SCREEN_H - SCAN_AREA_SIZE) / 2;
const LEFT_OFFSET = (SCREEN_W - SCAN_AREA_SIZE) / 2;

// Custom cubic easing (approximation of easeOutCubic)
const easeOutCubic = Easing.bezier(0.33, 1, 0.68, 1);

interface QRScannerScreenProps {
  onClose: () => void;
  onCodeDetected: (result: BarcodeResult) => void;
  onFlashToggle?: (on: boolean) => void;
  onScanAgain?: () => void;
}

export interface QRScannerScreenHandle {
  triggerDetection: (result: BarcodeResult) => void;
}

export const QRScannerScreenWithRef = React.forwardRef<QRScannerScreenHandle, QRScannerScreenProps>(
  ({ onClose, onCodeDetected, onFlashToggle, onScanAgain }, ref) => {
    const [flashOn, setFlashOn] = useState(false);
    const [detected, setDetected] = useState(false);
    const [result, setResult] = useState<BarcodeResult | null>(null);
    const [copied, setCopied] = useState(false);

    // Entrance animation
    const entranceOpacity = useRef(new Animated.Value(0)).current;
    const entranceScale = useRef(new Animated.Value(0.9)).current;

    // Corner pulse
    const pulseAnim = useRef(new Animated.Value(0)).current;

    // Scan line
    const scanLineAnim = useRef(new Animated.Value(0)).current;

    // Detection
    const detectionAnim = useRef(new Animated.Value(0)).current;
    const cornerColorAnim = useRef(new Animated.Value(0)).current;

    // Post-scan
    const overlayFadeAnim = useRef(new Animated.Value(1)).current;
    const resultSlideAnim = useRef(new Animated.Value(SCREEN_H)).current;
    const scanAreaZoom = useRef(new Animated.Value(1)).current;

    // Freeze effect
    const freezeOpacity = useRef(new Animated.Value(0)).current;

    const scanLineLoop = useRef<Animated.CompositeAnimation | null>(null);
    const pulseLoopRef = useRef<Animated.CompositeAnimation | null>(null);
    const detectedRef = useRef(false);

    // Entrance animation - fade + scale-in
    useEffect(() => {
      Animated.parallel([
        Animated.timing(entranceOpacity, {
          toValue: 1,
          duration: ENTRANCE_DURATION,
          easing: easeOutCubic,
          useNativeDriver: true,
        }),
        Animated.timing(entranceScale, {
          toValue: 1,
          duration: ENTRANCE_DURATION,
          easing: easeOutCubic,
          useNativeDriver: true,
        }),
      ]).start();
    }, [entranceOpacity, entranceScale]);

    // Corner brackets pulse - very subtle scale 1.00 → 1.03
    useEffect(() => {
      const pulse = Animated.loop(
        Animated.sequence([
          Animated.timing(pulseAnim, {
            toValue: 1,
            duration: PULSE_DURATION / 2,
            easing: easeOutCubic,
            useNativeDriver: true,
          }),
          Animated.timing(pulseAnim, {
            toValue: 0,
            duration: PULSE_DURATION / 2,
            easing: easeOutCubic,
            useNativeDriver: true,
          }),
        ]),
      );
      pulseLoopRef.current = pulse;
      pulse.start();
      return () => pulse.stop();
    }, [pulseAnim]);

    // Scan line - top to bottom, 1.4s cycle
    useEffect(() => {
      const loop = Animated.loop(
        Animated.sequence([
          Animated.timing(scanLineAnim, {
            toValue: 1,
            duration: SCAN_LINE_DURATION,
            easing: Easing.inOut(Easing.ease),
            useNativeDriver: true,
          }),
          Animated.timing(scanLineAnim, {
            toValue: 0,
            duration: 0,
            useNativeDriver: true,
          }),
        ]),
      );
      scanLineLoop.current = loop;
      loop.start();
      return () => loop.stop();
    }, [scanLineAnim]);

    const triggerDetection = useCallback((barcodeResult: BarcodeResult) => {
      if (detectedRef.current) return;
      detectedRef.current = true;
      setDetected(true);

      // Vibration feedback - short snap
      try { Vibration.vibrate(50); } catch (_) {}

      // Stop scan line immediately
      scanLineLoop.current?.stop();

      // Stop corner pulse
      pulseLoopRef.current?.stop();
      pulseAnim.setValue(0);

      // 1) Corner color: white → yellow (snap)
      Animated.timing(cornerColorAnim, {
        toValue: 1,
        duration: DETECTION_DURATION / 2,
        easing: Easing.out(Easing.ease),
        useNativeDriver: false,
      }).start();

      // 2) Scale snap: 1.0 → 1.05 → 1.0
      Animated.sequence([
        Animated.timing(detectionAnim, {
          toValue: 1,
          duration: DETECTION_DURATION / 2,
          easing: Easing.out(Easing.ease),
          useNativeDriver: true,
        }),
        Animated.timing(detectionAnim, {
          toValue: 0,
          duration: DETECTION_DURATION / 2,
          easing: easeOutCubic,
          useNativeDriver: true,
        }),
      ]).start();

      // 3) Freeze flash: brief white overlay flash simulating camera freeze
      Animated.sequence([
        Animated.timing(freezeOpacity, {
          toValue: 0.15,
          duration: 50,
          useNativeDriver: true,
        }),
        Animated.timing(freezeOpacity, {
          toValue: 0,
          duration: 150,
          useNativeDriver: true,
        }),
      ]).start();

      // 4) After detection confirmed - post-scan transition (250-350ms)
      setTimeout(() => {
        // Slight zoom on scan area
        Animated.timing(scanAreaZoom, {
          toValue: 1.02,
          duration: POST_SCAN_DURATION,
          easing: easeOutCubic,
          useNativeDriver: true,
        }).start();

        // Fade out overlay
        Animated.timing(overlayFadeAnim, {
          toValue: 0,
          duration: POST_SCAN_DURATION,
          easing: easeOutCubic,
          useNativeDriver: true,
        }).start();

        // Show result card
        setResult(barcodeResult);
        Animated.spring(resultSlideAnim, {
          toValue: 0,
          useNativeDriver: true,
          tension: 65,
          friction: 10,
        }).start();

        onCodeDetected(barcodeResult);
      }, DETECTION_DURATION + 50);
    }, [pulseAnim, cornerColorAnim, detectionAnim, freezeOpacity, scanAreaZoom, overlayFadeAnim, resultSlideAnim, onCodeDetected]);

    React.useImperativeHandle(ref, () => ({
      triggerDetection,
    }), [triggerDetection]);

    const handleScanAgain = () => {
      detectedRef.current = false;
      setDetected(false);
      setResult(null);
      setCopied(false);

      // Reset all animations
      cornerColorAnim.setValue(0);
      overlayFadeAnim.setValue(1);
      resultSlideAnim.setValue(SCREEN_H);
      scanLineAnim.setValue(0);
      scanAreaZoom.setValue(1);
      detectionAnim.setValue(0);

      // Restart scan line
      const loop = Animated.loop(
        Animated.sequence([
          Animated.timing(scanLineAnim, {
            toValue: 1,
            duration: SCAN_LINE_DURATION,
            easing: Easing.inOut(Easing.ease),
            useNativeDriver: true,
          }),
          Animated.timing(scanLineAnim, {
            toValue: 0,
            duration: 0,
            useNativeDriver: true,
          }),
        ]),
      );
      scanLineLoop.current = loop;
      loop.start();

      // Restart corner pulse
      const pulse = Animated.loop(
        Animated.sequence([
          Animated.timing(pulseAnim, {
            toValue: 1,
            duration: PULSE_DURATION / 2,
            easing: easeOutCubic,
            useNativeDriver: true,
          }),
          Animated.timing(pulseAnim, {
            toValue: 0,
            duration: PULSE_DURATION / 2,
            easing: easeOutCubic,
            useNativeDriver: true,
          }),
        ]),
      );
      pulseLoopRef.current = pulse;
      pulse.start();

      onScanAgain?.();
    };

    const handleCopy = () => {
      if (result) {
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }
    };

    const handleToggleFlash = () => {
      const newState = !flashOn;
      setFlashOn(newState);
      onFlashToggle?.(newState);
    };

    // Interpolations
    const cornerScale = pulseAnim.interpolate({
      inputRange: [0, 1],
      outputRange: [1.0, 1.03],
    });

    const cornerOpacity = pulseAnim.interpolate({
      inputRange: [0, 1],
      outputRange: [0.85, 1.0],
    });

    const detectionScale = detectionAnim.interpolate({
      inputRange: [0, 1],
      outputRange: [1.0, 1.05],
    });

    const scanLineTranslateY = scanLineAnim.interpolate({
      inputRange: [0, 1],
      outputRange: [0, SCAN_AREA_SIZE - SCAN_LINE_HEIGHT],
    });

    // White → Yellow on detection
    const cornerColor = cornerColorAnim.interpolate({
      inputRange: [0, 1],
      outputRange: ['#FFFFFF', '#FFC107'],
    });

    const renderCorner = (position: 'topLeft' | 'topRight' | 'bottomLeft' | 'bottomRight') => {
      const isTop = position.includes('top');
      const isLeft = position.includes('Left');

      const cornerPositionStyle: any = {
        position: 'absolute' as const,
        top: isTop ? TOP_OFFSET - CORNER_THICKNESS : TOP_OFFSET + SCAN_AREA_SIZE - CORNER_LENGTH,
        left: isLeft ? LEFT_OFFSET - CORNER_THICKNESS : LEFT_OFFSET + SCAN_AREA_SIZE - CORNER_LENGTH,
      };

      return (
        <Animated.View
          key={position}
          style={[
            cornerPositionStyle,
            {
              width: CORNER_LENGTH + CORNER_THICKNESS,
              height: CORNER_LENGTH + CORNER_THICKNESS,
              opacity: detected ? 1 : cornerOpacity,
              transform: [{ scale: detected ? detectionScale : cornerScale }],
            },
          ]}
        >
          {/* Horizontal bar */}
          <Animated.View
            style={{
              position: 'absolute',
              top: isTop ? 0 : CORNER_LENGTH,
              left: 0,
              width: CORNER_LENGTH + CORNER_THICKNESS,
              height: CORNER_THICKNESS,
              backgroundColor: cornerColor,
              borderTopLeftRadius: isTop && isLeft ? CORNER_RADIUS : 0,
              borderTopRightRadius: isTop && !isLeft ? CORNER_RADIUS : 0,
              borderBottomLeftRadius: !isTop && isLeft ? CORNER_RADIUS : 0,
              borderBottomRightRadius: !isTop && !isLeft ? CORNER_RADIUS : 0,
            }}
          />
          {/* Vertical bar */}
          <Animated.View
            style={{
              position: 'absolute',
              top: 0,
              left: isLeft ? 0 : CORNER_LENGTH,
              width: CORNER_THICKNESS,
              height: CORNER_LENGTH + CORNER_THICKNESS,
              backgroundColor: cornerColor,
              borderTopLeftRadius: isTop && isLeft ? CORNER_RADIUS : 0,
              borderTopRightRadius: isTop && !isLeft ? CORNER_RADIUS : 0,
              borderBottomLeftRadius: !isTop && isLeft ? CORNER_RADIUS : 0,
              borderBottomRightRadius: !isTop && !isLeft ? CORNER_RADIUS : 0,
            }}
          />
        </Animated.View>
      );
    };

    return (
      <Animated.View
        style={[
          StyleSheet.absoluteFill,
          {
            opacity: entranceOpacity,
            transform: [{ scale: entranceScale }],
          },
        ]}
      >
        {/* Fullscreen camera */}
        <Animated.View style={[StyleSheet.absoluteFill, { transform: [{ scale: scanAreaZoom }] }]}>
          <PharmaScannerCameraView style={StyleSheet.absoluteFill} />
        </Animated.View>

        {/* Camera freeze flash overlay */}
        <Animated.View
          style={[StyleSheet.absoluteFill, { backgroundColor: '#FFF', opacity: freezeOpacity }]}
          pointerEvents="none"
        />

        {/* Dark overlay with cutout */}
        <Animated.View style={[StyleSheet.absoluteFill, { opacity: overlayFadeAnim }]} pointerEvents="box-none">
          {/* Top rect */}
          <View style={[styles.overlayRect, { top: 0, left: 0, right: 0, height: TOP_OFFSET }]} />
          {/* Bottom rect */}
          <View style={[styles.overlayRect, { bottom: 0, left: 0, right: 0, height: TOP_OFFSET }]} />
          {/* Left rect */}
          <View style={[styles.overlayRect, { top: TOP_OFFSET, left: 0, width: LEFT_OFFSET, height: SCAN_AREA_SIZE }]} />
          {/* Right rect */}
          <View style={[styles.overlayRect, { top: TOP_OFFSET, right: 0, width: LEFT_OFFSET, height: SCAN_AREA_SIZE }]} />

          {/* Corner brackets */}
          {renderCorner('topLeft')}
          {renderCorner('topRight')}
          {renderCorner('bottomLeft')}
          {renderCorner('bottomRight')}

          {/* Scan line */}
          {!detected && (
            <Animated.View
              style={[
                styles.scanLineContainer,
                {
                  top: TOP_OFFSET,
                  left: LEFT_OFFSET,
                  width: SCAN_AREA_SIZE,
                  transform: [{ translateY: scanLineTranslateY }],
                },
              ]}
            >
              <View style={styles.scanLineOuter} />
              <View style={styles.scanLineInner} />
              <View style={styles.scanLineCore} />
              <View style={styles.scanLineInner} />
              <View style={styles.scanLineOuter} />
            </Animated.View>
          )}

          {/* Instruction text */}
          <View style={styles.instructionContainer}>
            <Text style={styles.instructionText}>
              {detected ? 'Đã nhận diện mã QR' : 'Đưa mã QR vào khung để quét'}
            </Text>
          </View>
        </Animated.View>

        {/* Top bar */}
        <View style={styles.topBar}>
          <TouchableOpacity style={styles.topBarButton} onPress={onClose}>
            <Text style={styles.backArrow}>{'‹'}</Text>
          </TouchableOpacity>
          <Text style={styles.topBarTitle}>Quét mã</Text>
          <TouchableOpacity
            style={[styles.topBarButton, flashOn && styles.topBarButtonActive]}
            onPress={handleToggleFlash}
          >
            <Text style={styles.flashIcon}>{flashOn ? '⚡' : '🔦'}</Text>
          </TouchableOpacity>
        </View>

        {/* Result bottom sheet */}
        {result && (
          <Animated.View
            style={[
              styles.resultSheet,
              { transform: [{ translateY: resultSlideAnim }] },
            ]}
          >
            <View style={styles.resultSheetHandle} />
            <View style={styles.resultFormatBadge}>
              <Text style={styles.resultFormatText}>{result.format}</Text>
            </View>
            <Text style={styles.resultValue} numberOfLines={5} selectable>
              {result.value}
            </Text>
            <TouchableOpacity style={styles.resultCopyButton} onPress={handleCopy}>
              <Text style={styles.resultCopyText}>
                {copied ? 'Đã sao chép!' : 'Nhấn để sao chép'}
              </Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.scanAgainButton} onPress={handleScanAgain}>
              <Text style={styles.scanAgainText}>Quét lại</Text>
            </TouchableOpacity>
          </Animated.View>
        )}
      </Animated.View>
    );
  },
);

const styles = StyleSheet.create({
  overlayRect: {
    position: 'absolute',
    backgroundColor: `rgba(0,0,0,${OVERLAY_OPACITY})`,
  },
  scanLineContainer: {
    position: 'absolute',
    height: SCAN_LINE_HEIGHT,
    flexDirection: 'row',
  },
  scanLineOuter: {
    flex: 1,
    backgroundColor: 'rgba(76, 175, 80, 0.1)',
  },
  scanLineInner: {
    flex: 2,
    backgroundColor: 'rgba(76, 175, 80, 0.35)',
  },
  scanLineCore: {
    flex: 4,
    backgroundColor: '#4CAF50',
    ...Platform.select({
      ios: {
        shadowColor: '#4CAF50',
        shadowOffset: { width: 0, height: 0 },
        shadowOpacity: 0.9,
        shadowRadius: 8,
      },
      android: {
        elevation: 3,
      },
    }),
  },
  instructionContainer: {
    position: 'absolute',
    top: TOP_OFFSET + SCAN_AREA_SIZE + 30,
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  instructionText: {
    color: '#FFFFFF',
    fontSize: 15,
    fontWeight: '400',
    textAlign: 'center',
    opacity: 0.9,
  },
  topBar: {
    position: 'absolute',
    top: Platform.OS === 'ios' ? 54 : 32,
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
  },
  topBarButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(0,0,0,0.35)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  topBarButtonActive: {
    backgroundColor: 'rgba(255,193,7,0.5)',
  },
  backArrow: {
    color: '#FFFFFF',
    fontSize: 26,
    fontWeight: '300',
    marginTop: -2,
  },
  flashIcon: {
    fontSize: 16,
  },
  topBarTitle: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '600',
  },
  resultSheet: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: '#FFFFFF',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    padding: 20,
    paddingBottom: Platform.OS === 'ios' ? 40 : 24,
    alignItems: 'center',
    ...Platform.select({
      ios: {
        shadowColor: '#000',
        shadowOffset: { width: 0, height: -4 },
        shadowOpacity: 0.15,
        shadowRadius: 12,
      },
      android: {
        elevation: 12,
      },
    }),
  },
  resultSheetHandle: {
    width: 36,
    height: 4,
    borderRadius: 2,
    backgroundColor: '#E0E0E0',
    marginBottom: 16,
  },
  resultFormatBadge: {
    backgroundColor: '#1976D2',
    borderRadius: 4,
    paddingVertical: 3,
    paddingHorizontal: 10,
    marginBottom: 12,
  },
  resultFormatText: {
    color: '#FFFFFF',
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  resultValue: {
    fontSize: 15,
    fontWeight: '500',
    color: '#212121',
    textAlign: 'center',
    marginBottom: 16,
    paddingHorizontal: 16,
    lineHeight: 22,
  },
  resultCopyButton: {
    backgroundColor: '#F5F5F5',
    borderRadius: 8,
    paddingVertical: 10,
    paddingHorizontal: 24,
    marginBottom: 10,
  },
  resultCopyText: {
    color: '#424242',
    fontSize: 14,
    fontWeight: '500',
  },
  scanAgainButton: {
    backgroundColor: '#1976D2',
    borderRadius: 8,
    paddingVertical: 10,
    paddingHorizontal: 24,
  },
  scanAgainText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '600',
  },
});
