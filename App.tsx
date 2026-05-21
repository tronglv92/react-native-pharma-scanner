import React, { useState, useEffect } from 'react';
import {
  SafeAreaView,
  StyleSheet,
  Text,
  View,
  TouchableOpacity,
  Image,
  Alert,
} from 'react-native';
import { scanner, PharmaScannerCameraView } from './src';
import type { CapturedImage } from './src';

function App(): React.JSX.Element {
  const [ping, setPing] = useState<string>('...');
  const [version, setVersion] = useState<string>('...');
  const [cameraActive, setCameraActive] = useState(false);
  const [capturedImage, setCapturedImage] = useState<CapturedImage | null>(null);

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

  const handleStartCamera = () => {
    try {
      scanner.startCamera();
      setCameraActive(true);
      setCapturedImage(null);
    } catch (e) {
      Alert.alert('Error', String(e));
    }
  };

  const handleStopCamera = () => {
    try {
      scanner.stopCamera();
      setCameraActive(false);
    } catch (e) {
      Alert.alert('Error', String(e));
    }
  };

  const handleCapture = async () => {
    try {
      const result = await scanner.capturePhoto();
      setCapturedImage(result);
    } catch (e) {
      Alert.alert('Capture Error', String(e));
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

  return (
    <SafeAreaView style={styles.container}>
      <Text style={styles.title}>Pharma Scanner</Text>

      <View style={styles.card}>
        <Text style={styles.label}>ping()</Text>
        <Text style={styles.value}>{ping}</Text>
      </View>
      <View style={styles.card}>
        <Text style={styles.label}>getVersion()</Text>
        <Text style={styles.value}>{version}</Text>
      </View>

      {!cameraActive ? (
        <TouchableOpacity style={styles.button} onPress={handleStartCamera}>
          <Text style={styles.buttonText}>Start Camera</Text>
        </TouchableOpacity>
      ) : (
        <View style={styles.cameraContainer}>
          <PharmaScannerCameraView style={styles.cameraPreview} />

          <View style={styles.controls}>
            <TouchableOpacity style={styles.controlButton} onPress={handleCapture}>
              <Text style={styles.controlText}>Capture</Text>
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
          </View>

          <View style={styles.controls}>
            <TouchableOpacity style={styles.controlButton} onPress={() => handleZoom(1.0)}>
              <Text style={styles.controlText}>1x</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.controlButton} onPress={() => handleZoom(2.0)}>
              <Text style={styles.controlText}>2x</Text>
            </TouchableOpacity>
          </View>
        </View>
      )}

      {capturedImage && (
        <View style={styles.resultContainer}>
          <Image source={{ uri: capturedImage.uri }} style={styles.capturedImage} />
          <Text style={styles.label}>
            {capturedImage.width} x {capturedImage.height}
          </Text>
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    backgroundColor: '#f5f5f5',
    paddingTop: 40,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 16,
  },
  card: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 12,
    marginVertical: 4,
    width: 250,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  label: {
    fontSize: 14,
    color: '#666',
    marginBottom: 4,
  },
  value: {
    fontSize: 20,
    fontWeight: '600',
    color: '#333',
  },
  button: {
    backgroundColor: '#007AFF',
    borderRadius: 8,
    paddingVertical: 12,
    paddingHorizontal: 24,
    marginTop: 16,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  cameraContainer: {
    width: '100%',
    alignItems: 'center',
    marginTop: 12,
  },
  cameraPreview: {
    width: 300,
    height: 300,
    borderRadius: 8,
    overflow: 'hidden',
  },
  controls: {
    flexDirection: 'row',
    marginTop: 8,
    gap: 8,
  },
  controlButton: {
    backgroundColor: '#333',
    borderRadius: 6,
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  controlText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  resultContainer: {
    alignItems: 'center',
    marginTop: 12,
  },
  capturedImage: {
    width: 150,
    height: 150,
    borderRadius: 8,
    marginBottom: 4,
  },
});

export default App;
