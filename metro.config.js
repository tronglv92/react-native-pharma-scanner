const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');
const path = require('path');

/**
 * Metro configuration
 * https://reactnative.dev/docs/metro
 *
 * @type {import('@react-native/metro-config').MetroConfig}
 */
const config = {
  transformer: {
    babelTransformerPath: path.resolve(__dirname, 'yaml-transformer.js'),
  },
  resolver: {
    sourceExts: [...getDefaultConfig(__dirname).resolver.sourceExts, 'yaml', 'yml'],
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
