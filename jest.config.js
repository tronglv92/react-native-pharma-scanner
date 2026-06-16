module.exports = {
  preset: '@react-native/jest-preset',
  testPathIgnorePatterns: [
    '/node_modules/',
    '/pharmascanner/',
    '/example/node_modules/',
  ],
  moduleNameMapper: {
    '^react-native-config$': '<rootDir>/__mocks__/react-native-config.ts',
    '^react-native-image-picker$':
      '<rootDir>/__mocks__/react-native-image-picker.ts',
    '^react-native-pharma-scanner$': '<rootDir>/src/index.ts',
  },
  collectCoverageFrom: [
    'src/utils/**/*.ts',
    'src/schemas/**/*.ts',
    'src/providers/**/*.ts',
    'src/extract.ts',
    'src/document-types.ts',
    '!src/**/*.d.ts',
  ],
  coverageThreshold: {
    'src/utils/': {
      statements: 80,
      branches: 70,
      functions: 80,
      lines: 80,
    },
  },
};
