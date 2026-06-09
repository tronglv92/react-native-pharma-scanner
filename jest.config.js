module.exports = {
  preset: '@react-native/jest-preset',
  testPathIgnorePatterns: [
    '/node_modules/',
    '/pharmascanner/',
  ],
  moduleNameMapper: {
    '^react-native-config$': '<rootDir>/__mocks__/react-native-config.ts',
    '^react-native-image-picker$':
      '<rootDir>/__mocks__/react-native-image-picker.ts',
  },
  collectCoverageFrom: [
    'src/utils/**/*.ts',
    'src/mistral.ts',
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
