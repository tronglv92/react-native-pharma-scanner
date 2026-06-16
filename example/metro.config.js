const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');
const path = require('path');

const root = path.resolve(__dirname, '..');

/**
 * Metro configuration for the example app.
 * Resolves the parent library via watchFolders.
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
const config = {
  watchFolders: [root],
  transformer: {
    babelTransformerPath: path.resolve(__dirname, 'yaml-transformer.js'),
  },
  resolver: {
    sourceExts: [...getDefaultConfig(__dirname).resolver.sourceExts, 'yaml', 'yml'],
    // Ensure the library's src/ is resolved as 'react-native-pharma-scanner'
    nodeModulesPaths: [
      path.resolve(__dirname, 'node_modules'),
      path.resolve(root, 'node_modules'),
    ],
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
