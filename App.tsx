import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  SafeAreaView,
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  Image,
  Alert,
  ScrollView,
  ActivityIndicator,
  Vibration,
  Platform,
} from 'react-native';
import { scanner, PharmaScannerCameraView } from './src';
import type { CapturedImage, DocumentDetection, BarcodeResult, BarcodeFormat } from './src';

type AppMode = 'home' | 'document' | 'barcode-capture' | 'barcode-auto';

const ALL_BARCODE_FORMATS: BarcodeFormat[] = [
  'QR_CODE',
  'CODE_128',
  'PDF_417',
  'DATA_MATRIX',
  'EAN_13',
  'EAN_8',
];

function App(): React.JSX.Element {
  const [ping, setPing] = useState<string>('...');
  const [version, setVersion] = useState<string>('...');
  const [appMode, setAppMode] = useState<AppMode>('home');
  const [cameraActive, setCameraActive] = useState(false);
  const [capturedImage, setCapturedImage] = useState<CapturedImage | null>(null);
  const [correctedImage, setCorrectedImage] = useState<CapturedImage | null>(null);
  const [detection, setDetection] = useState<DocumentDetection | null>(null);
  const [autoCapture, setAutoCapture] = useState(false);
  const [isCapturing, setIsCapturing] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [scannedImages, setScannedImages] = useState<CapturedImage[]>([]);
  const [isScanning, setIsScanning] = useState(false);

  // Barcode state
  const [barcodeResults, setBarcodeResults] = useState<BarcodeResult[]>([]);
  const [continuousScanActive, setContinuousScanActive] = useState(false);
  const [continuousResults, setContinuousResults] = useState<BarcodeResult[]>([]);
  const [scanCount, setScanCount] = useState(0);

  const stableStartRef = useRef<number | null>(null);
  const isCapturingRef = useRef(false);
  const scanCountRef = useRef(0);

  useEffect(() => {
    try {
      setPing(scanner.ping());
      setVersion(scanner.getVersion());
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setPing(`Error: ${msg}`);
      setVersion(`Error: ${msg}`);
    }
  }, []);

  const captureAndCorrect = useCallback(async () => {
    if (isCapturingRef.current) return;
    isCapturingRef.current = true;
    setIsCapturing(true);

    try {
      try { Vibration.vibrate(100); } catch (_) {}

      const photo = await scanner.capturePhoto();
      setCapturedImage(photo);

      scanner.stopCamera();
      setCameraActive(false);

      setIsProcessing(true);
      const det = await scanner.detectDocument(photo.uri);

      if (det.detected) {
        try {
          const corrected = await scanner.cropAndCorrect(photo.uri, det.corners);
          setCorrectedImage(corrected);
        } catch (e) {
          console.warn('cropAndCorrect failed:', e);
          Alert.alert('Correction Failed', 'Document was detected but perspective correction failed.');
        }
      } else {
        Alert.alert('No Document Found', 'Could not detect a document in the captured photo. Try again with better framing.');
      }
    } catch (e) {
      Alert.alert('Capture Error', String(e));
    } finally {
      setIsProcessing(false);
      setIsCapturing(false);
      isCapturingRef.current = false;
    }
  }, []);

  useEffect(() => {
    if (!cameraActive || appMode !== 'document') {
      setDetection(null);
      stableStartRef.current = null;
      return;
    }

    scanner.setOnDocumentDetected((det: DocumentDetection) => {
      setDetection(det);

      if (det.detected && det.isStable) {
        if (stableStartRef.current === null) {
          stableStartRef.current = Date.now();
        }

        if (autoCapture && stableStartRef.current && Date.now() - stableStartRef.current >= 1000) {
          stableStartRef.current = null;
          captureAndCorrect();
        }
      } else {
        stableStartRef.current = null;
      }
    });

    return () => {
      scanner.setOnDocumentDetected(() => {});
    };
  }, [cameraActive, autoCapture, captureAndCorrect, appMode]);

  // Auto-start continuous barcode scanning in auto mode
  useEffect(() => {
    if (!cameraActive || appMode !== 'barcode-auto') {
      return;
    }

    // Small delay to ensure the camera session is ready
    const timer = setTimeout(() => {
      setContinuousResults([]);
      setScanCount(0);
      scanCountRef.current = 0;
      scanner.startContinuousScan(ALL_BARCODE_FORMATS, (codes: BarcodeResult[]) => {
        scanCountRef.current += 1;
        setScanCount(scanCountRef.current);
        setContinuousResults(codes);
      });
      setContinuousScanActive(true);
    }, 500);

    return () => {
      clearTimeout(timer);
      if (continuousScanActive) {
        scanner.stopContinuousScan();
        setContinuousScanActive(false);
      }
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cameraActive, appMode]);

  const handleStartCamera = (mode: AppMode) => {
    try {
      scanner.startCamera();
      setCameraActive(true);
      setAppMode(mode);
      setCapturedImage(null);
      setCorrectedImage(null);
      setScannedImages([]);
      setBarcodeResults([]);
      setContinuousResults([]);
      setScanCount(0);
      scanCountRef.current = 0;
      stableStartRef.current = null;
    } catch (e) {
      Alert.alert('Error', String(e));
    }
  };

  const handleStopCamera = () => {
    try {
      if (continuousScanActive) {
        scanner.stopContinuousScan();
        setContinuousScanActive(false);
      }
      scanner.stopCamera();
      setCameraActive(false);
    } catch (e) {
      Alert.alert('Error', String(e));
    }
  };

  const handleCapture = () => {
    captureAndCorrect();
  };

  const handleCropCorrect = async () => {
    if (!capturedImage) return;

    setIsProcessing(true);
    try {
      const det = await scanner.detectDocument(capturedImage.uri);
      if (det.detected) {
        const result = await scanner.cropAndCorrect(capturedImage.uri, det.corners);
        setCorrectedImage(result);
      } else {
        Alert.alert('No Document Found', 'Could not detect a document in this image.');
      }
    } catch (e) {
      Alert.alert('Crop & Correct Error', String(e));
    } finally {
      setIsProcessing(false);
    }
  };

  const handleScanDocument = async () => {
    setIsScanning(true);
    setAppMode('document');
    setCapturedImage(null);
    setCorrectedImage(null);
    setScannedImages([]);
    try {
      const results = await scanner.scanDocument();
      if (results.length > 0) {
        setScannedImages(results);
      }
    } catch (e) {
      Alert.alert('Scan Error', String(e));
    } finally {
      setIsScanning(false);
    }
  };

  // Barcode: capture photo then scan barcodes on it
  const handleCaptureAndScanBarcode = async () => {
    if (isCapturingRef.current) return;
    isCapturingRef.current = true;
    setIsCapturing(true);

    try {
      try { Vibration.vibrate(100); } catch (_) {}

      const photo = await scanner.capturePhoto();
      setCapturedImage(photo);

      setIsProcessing(true);
      const results = await scanner.scanBarcodes({
        imageUri: photo.uri,
        formats: ALL_BARCODE_FORMATS,
      });
      setBarcodeResults(results);

      if (results.length === 0) {
        Alert.alert('No Barcodes Found', 'No barcodes or QR codes detected in the captured photo.');
      }
    } catch (e) {
      Alert.alert('Barcode Scan Error', String(e));
    } finally {
      setIsProcessing(false);
      setIsCapturing(false);
      isCapturingRef.current = false;
    }
  };

  const handleFlash = (mode: 'on' | 'off') => {
    try {
      scanner.setFlash(mode);
    } catch (e) {
      Alert.alert('Flash Error', String(e));
    }
  };

  const handleZoom = (factor: number) => {
    try {
      scanner.setZoom(factor);
    } catch (e) {
      Alert.alert('Zoom Error', String(e));
    }
  };

  const handleReset = () => {
    setCapturedImage(null);
    setCorrectedImage(null);
    setScannedImages([]);
    setBarcodeResults([]);
    setContinuousResults([]);
    setScanCount(0);
    scanCountRef.current = 0;
    setAppMode('home');
  };

  const handleBackToHome = () => {
    if (cameraActive) {
      handleStopCamera();
    }
    handleReset();
  };

  const confPercent = detection?.detected
    ? `${Math.round((detection.confidence ?? 0) * 100)}%`
    : '--';

  const isAndroid = Platform.OS === 'android';
  const showingResults = capturedImage || scannedImages.length > 0 || barcodeResults.length > 0;

  const renderBarcodeResult = (result: BarcodeResult, index: number) => (
    <View key={index} style={styles.barcodeResultItem}>
      <View style={styles.barcodeFormatBadge}>
        <Text style={styles.barcodeFormatText}>{result.format}</Text>
      </View>
      <Text style={styles.barcodeValue} numberOfLines={3}>{result.value}</Text>
      {result.rawValue !== result.value && (
        <Text style={styles.barcodeRawValue} numberOfLines={2}>Raw: {result.rawValue}</Text>
      )}
      {result.boundingBox && (
        <Text style={styles.barcodeBounds}>
          Box: ({Math.round(result.boundingBox.x)}, {Math.round(result.boundingBox.y)}) {Math.round(result.boundingBox.width)}x{Math.round(result.boundingBox.height)}
        </Text>
      )}
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        <Text style={styles.title}>Pharma Scanner</Text>

        <View style={styles.row}>
          <View style={styles.card}>
            <Text style={styles.label}>ping()</Text>
            <Text style={styles.value}>{ping}</Text>
          </View>
          <View style={styles.card}>
            <Text style={styles.label}>version</Text>
            <Text style={styles.value}>{version}</Text>
          </View>
        </View>

        {/* Home screen buttons */}
        {appMode === 'home' && !cameraActive && !showingResults ? (
          <View style={styles.homeButtons}>
            {isAndroid ? (
              <TouchableOpacity style={styles.button} onPress={handleScanDocument}>
                <Text style={styles.buttonText}>Scan Document</Text>
              </TouchableOpacity>
            ) : (
              <TouchableOpacity style={styles.button} onPress={() => handleStartCamera('document')}>
                <Text style={styles.buttonText}>Scan Document</Text>
              </TouchableOpacity>
            )}
            <TouchableOpacity style={[styles.button, styles.barcodeButton]} onPress={() => handleStartCamera('barcode-capture')}>
              <Text style={styles.buttonText}>Capture & Scan Barcode</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[styles.button, styles.barcodeButton]} onPress={() => handleStartCamera('barcode-auto')}>
              <Text style={styles.buttonText}>Auto Scan Barcode</Text>
            </TouchableOpacity>
          </View>
        ) : null}

        {/* Scanning indicator */}
        {isScanning && (
          <View style={styles.processingContainer}>
            <ActivityIndicator size="large" color="#007AFF" />
            <Text style={styles.processingText}>Opening document scanner...</Text>
          </View>
        )}

        {/* Camera active — Document mode */}
        {cameraActive && appMode === 'document' && (
          <View style={styles.cameraContainer}>
            <PharmaScannerCameraView style={styles.cameraPreview} />

            <View style={styles.detectionBar}>
              <Text style={styles.detectionText}>
                {detection?.detected
                  ? `Conf: ${confPercent} | ${detection.isStable ? 'STABLE' : 'Moving...'}`
                  : 'Scanning...'}
              </Text>
              <TouchableOpacity
                style={[styles.autoToggle, autoCapture && styles.autoToggleActive]}
                onPress={() => setAutoCapture(!autoCapture)}>
                <Text style={styles.autoToggleText}>
                  Auto: {autoCapture ? 'ON' : 'OFF'}
                </Text>
              </TouchableOpacity>
            </View>

            {isCapturing && (
              <View style={styles.capturingOverlay}>
                <Text style={styles.capturingText}>Capturing...</Text>
              </View>
            )}

            <View style={styles.controls}>
              <TouchableOpacity style={styles.captureButton} onPress={handleCapture}>
                <Text style={styles.captureButtonText}>Capture & Correct</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={handleStopCamera}>
                <Text style={styles.controlText}>Stop</Text>
              </TouchableOpacity>
            </View>

            <View style={styles.controls}>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleFlash('on')}>
                <Text style={styles.controlText}>Flash On</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleFlash('off')}>
                <Text style={styles.controlText}>Flash Off</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleZoom(1.0)}>
                <Text style={styles.controlText}>1x</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleZoom(2.0)}>
                <Text style={styles.controlText}>2x</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}

        {/* Camera active — Barcode Capture & Scan mode */}
        {cameraActive && appMode === 'barcode-capture' && (
          <View style={styles.cameraContainer}>
            <PharmaScannerCameraView style={styles.cameraPreview} />

            <View style={styles.detectionBar}>
              <Text style={styles.detectionText}>Capture & Scan mode</Text>
            </View>

            {isCapturing && (
              <View style={styles.capturingOverlay}>
                <Text style={styles.capturingText}>Scanning...</Text>
              </View>
            )}

            <View style={styles.controls}>
              <TouchableOpacity style={styles.captureButton} onPress={handleCaptureAndScanBarcode}>
                <Text style={styles.captureButtonText}>Capture & Scan</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={handleStopCamera}>
                <Text style={styles.controlText}>Stop</Text>
              </TouchableOpacity>
            </View>

            <View style={styles.controls}>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleFlash('on')}>
                <Text style={styles.controlText}>Flash On</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleFlash('off')}>
                <Text style={styles.controlText}>Flash Off</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleZoom(1.0)}>
                <Text style={styles.controlText}>1x</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleZoom(2.0)}>
                <Text style={styles.controlText}>2x</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}

        {/* Camera active — Barcode Auto Scan mode */}
        {cameraActive && appMode === 'barcode-auto' && (
          <View style={styles.cameraContainer}>
            <PharmaScannerCameraView style={styles.cameraPreview} />

            <View style={styles.detectionBar}>
              <Text style={styles.detectionText}>
                {continuousResults.length > 0
                  ? `Detected ${continuousResults.length} code${continuousResults.length > 1 ? 's' : ''}`
                  : 'Point at a barcode...'}
              </Text>
            </View>

            <View style={styles.controls}>
              <TouchableOpacity style={styles.controlButton} onPress={handleStopCamera}>
                <Text style={styles.controlText}>Stop</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleFlash('on')}>
                <Text style={styles.controlText}>Flash On</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleFlash('off')}>
                <Text style={styles.controlText}>Flash Off</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleZoom(1.0)}>
                <Text style={styles.controlText}>1x</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={() => handleZoom(2.0)}>
                <Text style={styles.controlText}>2x</Text>
              </TouchableOpacity>
            </View>

            {continuousResults.length > 0 && (
              <View style={styles.continuousResultsContainer}>
                <Text style={[styles.sectionTitle, { color: '#9C27B0' }]}>
                  Detected ({continuousResults.length} codes)
                </Text>
                {continuousResults.map(renderBarcodeResult)}
              </View>
            )}
          </View>
        )}

        {/* Processing indicator */}
        {isProcessing && (
          <View style={styles.processingContainer}>
            <ActivityIndicator size="large" color="#007AFF" />
            <Text style={styles.processingText}>
              {appMode.startsWith('barcode') ? 'Scanning barcodes...' : 'Detecting & correcting...'}
            </Text>
          </View>
        )}

        {/* Captured image (document mode) */}
        {capturedImage && !isProcessing && appMode === 'document' && (
          <View style={styles.resultContainer}>
            <Text style={styles.sectionTitle}>Captured Photo</Text>
            <Image source={{ uri: capturedImage.uri }} style={styles.capturedImage} />
            <Text style={styles.label}>
              {capturedImage.width} x {capturedImage.height}
            </Text>
            {!correctedImage && (
              <TouchableOpacity style={styles.cropButton} onPress={handleCropCorrect}>
                <Text style={styles.buttonText}>Detect & Correct</Text>
              </TouchableOpacity>
            )}
          </View>
        )}

        {/* Corrected image */}
        {correctedImage && !isProcessing && (
          <View style={styles.resultContainer}>
            <Text style={[styles.sectionTitle, { color: '#4CAF50' }]}>Corrected Image</Text>
            <Image source={{ uri: correctedImage.uri }} style={styles.correctedImage} />
            <Text style={styles.label}>
              {correctedImage.width} x {correctedImage.height}
            </Text>
          </View>
        )}

        {/* Scanned document images (from ML Kit) */}
        {scannedImages.length > 0 && (
          <View style={styles.resultContainer}>
            <Text style={[styles.sectionTitle, { color: '#4CAF50' }]}>Scanned Document</Text>
            {scannedImages.map((img, index) => (
              <View key={index} style={styles.scannedImageWrapper}>
                <Image source={{ uri: img.uri }} style={styles.correctedImage} />
                <Text style={styles.label}>
                  {img.width} x {img.height}
                </Text>
              </View>
            ))}
          </View>
        )}

        {/* Barcode scan results (one-shot) */}
        {barcodeResults.length > 0 && !isProcessing && (
          <View style={styles.resultContainer}>
            <Text style={[styles.sectionTitle, { color: '#9C27B0' }]}>
              Barcode Results ({barcodeResults.length} found)
            </Text>
            {capturedImage && (
              <>
                <Image source={{ uri: capturedImage.uri }} style={styles.capturedImage} />
                <Text style={styles.label}>
                  {capturedImage.width} x {capturedImage.height}
                </Text>
              </>
            )}
            {barcodeResults.map(renderBarcodeResult)}
          </View>
        )}

        {/* Back / restart buttons */}
        {(showingResults || (appMode !== 'home' && !cameraActive)) && !isProcessing && !isScanning && (
          <View style={styles.buttonGroup}>
            {appMode === 'barcode-capture' && !cameraActive && (
              <TouchableOpacity style={[styles.button, styles.barcodeButton]} onPress={() => handleStartCamera('barcode-capture')}>
                <Text style={styles.buttonText}>Scan Again</Text>
              </TouchableOpacity>
            )}
            {appMode === 'barcode-auto' && !cameraActive && (
              <TouchableOpacity style={[styles.button, styles.barcodeButton]} onPress={() => handleStartCamera('barcode-auto')}>
                <Text style={styles.buttonText}>Scan Again</Text>
              </TouchableOpacity>
            )}
            {appMode === 'document' && !cameraActive && (
              isAndroid ? (
                <TouchableOpacity style={styles.button} onPress={handleScanDocument}>
                  <Text style={styles.buttonText}>Scan Again</Text>
                </TouchableOpacity>
              ) : (
                <TouchableOpacity style={styles.button} onPress={() => handleStartCamera('document')}>
                  <Text style={styles.buttonText}>Scan Again</Text>
                </TouchableOpacity>
              )
            )}
            <TouchableOpacity style={[styles.button, styles.resetButton]} onPress={handleBackToHome}>
              <Text style={styles.buttonText}>Home</Text>
            </TouchableOpacity>
          </View>
        )}

        <View style={{ height: 40 }} />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scroll: {
    alignItems: 'center',
    paddingTop: 40,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 12,
  },
  row: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 8,
  },
  card: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 12,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
    minWidth: 120,
  },
  label: {
    fontSize: 13,
    color: '#666',
    marginBottom: 2,
  },
  value: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
  },
  homeButtons: {
    gap: 10,
    marginTop: 12,
    alignItems: 'center',
  },
  buttonGroup: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 12,
  },
  button: {
    backgroundColor: '#007AFF',
    borderRadius: 8,
    paddingVertical: 12,
    paddingHorizontal: 24,
  },
  barcodeButton: {
    backgroundColor: '#9C27B0',
  },
  resetButton: {
    backgroundColor: '#666',
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  cameraContainer: {
    width: '100%',
    alignItems: 'center',
    marginTop: 8,
  },
  cameraPreview: {
    width: 320,
    height: 420,
    borderRadius: 12,
    overflow: 'hidden',
  },
  detectionBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    width: 320,
    marginTop: 6,
    paddingHorizontal: 4,
  },
  detectionText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
  },
  autoToggle: {
    backgroundColor: '#666',
    borderRadius: 12,
    paddingVertical: 4,
    paddingHorizontal: 12,
  },
  autoToggleActive: {
    backgroundColor: '#4CAF50',
  },
  autoToggleText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
  capturingOverlay: {
    position: 'absolute',
    top: 180,
    backgroundColor: 'rgba(0,0,0,0.6)',
    borderRadius: 8,
    padding: 12,
  },
  capturingText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  controls: {
    flexDirection: 'row',
    marginTop: 8,
    gap: 8,
  },
  captureButton: {
    backgroundColor: '#007AFF',
    borderRadius: 6,
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  captureButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  controlButton: {
    backgroundColor: '#333',
    borderRadius: 6,
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  activeButton: {
    backgroundColor: '#E91E63',
  },
  controlText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  processingContainer: {
    alignItems: 'center',
    marginTop: 24,
    gap: 8,
  },
  processingText: {
    fontSize: 14,
    color: '#666',
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '700',
    color: '#333',
    marginBottom: 6,
  },
  resultContainer: {
    alignItems: 'center',
    marginTop: 16,
    backgroundColor: '#fff',
    borderRadius: 12,
    padding: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
    width: 340,
  },
  continuousResultsContainer: {
    width: 320,
    marginTop: 8,
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 10,
  },
  scannedImageWrapper: {
    alignItems: 'center',
    marginBottom: 8,
  },
  capturedImage: {
    width: 200,
    height: 260,
    borderRadius: 8,
    marginBottom: 4,
    resizeMode: 'contain',
  },
  correctedImage: {
    width: 280,
    height: 360,
    borderRadius: 8,
    marginBottom: 4,
    resizeMode: 'contain',
  },
  cropButton: {
    backgroundColor: '#FF9800',
    borderRadius: 8,
    paddingVertical: 10,
    paddingHorizontal: 20,
    marginTop: 8,
  },
  barcodeResultItem: {
    width: '100%',
    backgroundColor: '#f9f9f9',
    borderRadius: 8,
    padding: 10,
    marginTop: 6,
    borderLeftWidth: 4,
    borderLeftColor: '#9C27B0',
  },
  barcodeFormatBadge: {
    alignSelf: 'flex-start',
    backgroundColor: '#9C27B0',
    borderRadius: 4,
    paddingVertical: 2,
    paddingHorizontal: 8,
    marginBottom: 4,
  },
  barcodeFormatText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
  },
  barcodeValue: {
    fontSize: 15,
    fontWeight: '600',
    color: '#333',
    marginBottom: 2,
  },
  barcodeRawValue: {
    fontSize: 12,
    color: '#999',
    marginBottom: 2,
  },
  barcodeBounds: {
    fontSize: 11,
    color: '#aaa',
  },
});

export default App;
