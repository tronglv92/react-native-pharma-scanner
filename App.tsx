import React, { useState, useEffect } from 'react';
import { SafeAreaView, StyleSheet, Text, View } from 'react-native';
import { scanner } from './src';

function App(): React.JSX.Element {
  const [ping, setPing] = useState<string>('...');
  const [version, setVersion] = useState<string>('...');

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
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#f5f5f5',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 32,
  },
  card: {
    backgroundColor: '#fff',
    borderRadius: 8,
    padding: 16,
    marginVertical: 8,
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
});

export default App;
