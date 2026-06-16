module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './pharmascanner',
        packageName: 'com.margelo.nitro.PharmaScanner',
      },
      ios: {
        podspecPath: './react-native-pharma-scanner.podspec',
      },
    },
  },
};
