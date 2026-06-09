/**
 * @format
 */

import React from 'react';
import ReactTestRenderer from 'react-test-renderer';

jest.mock('../src/PharmaScannerCameraView', () => {
  const RN = require('react-native');
  return {
    PharmaScannerCameraView: (props: any) => RN.createElement
      ? RN.createElement(RN.View, { ...props, testID: 'camera-view-mock' })
      : require('react').createElement(RN.View, { ...props, testID: 'camera-view-mock' }),
  };
});

jest.mock('../src/QRScannerScreen', () => {
  const RN = require('react-native');
  const R = require('react');
  return {
    QRScannerScreenWithRef: R.forwardRef((_props: any, _ref: any) =>
      R.createElement(RN.View, { testID: 'qr-scanner-mock' }),
    ),
  };
});

import App from '../App';

test('renders correctly', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });
});
