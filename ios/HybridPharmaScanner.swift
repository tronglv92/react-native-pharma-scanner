import NitroModules

class HybridPharmaScanner: HybridPharmaScannerSpec {
  func ping() throws -> String {
    return "pong"
  }
  func getVersion() throws -> String {
    return "0.0.1"
  }
}
