import React

@objc(PharmaScannerCameraViewManager)
class PharmaScannerCameraViewManager: RCTViewManager {
  override static func requiresMainQueueSetup() -> Bool {
    return true
  }

  override func view() -> UIView! {
    return PharmaScannerCameraView()
  }
}
