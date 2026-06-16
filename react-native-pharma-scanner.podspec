require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-pharma-scanner"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["repository"]["url"]
  s.license      = package["license"]
  s.authors      = { "PharmaScanner" => "dev@pharmascanner.io" }
  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => package["repository"]["url"], :tag => s.version }
  s.swift_version = "5.0"
  s.module_name   = "ReactNativePharmaScanner"

  s.source_files = [
    "ios/**/*.{swift,m,h,mm}",
    "nitrogen/generated/shared/**/*.{hpp,cpp,h}",
    "nitrogen/generated/ios/**/*.{hpp,cpp,h,mm,swift}",
  ]

  # Mark headers that reference ReactNativePharmaScanner-Swift.h as private
  # to break the circular dependency: Swift -> import underlying module ->
  # umbrella header -> ReactNativePharmaScanner-Swift.h (not yet generated).
  # Note: Bridge.hpp does NOT reference Swift.h, so it must stay public
  # for Swift to resolve the margelo.nitro.PharmaScannerCxx.bridge namespace.
  s.private_header_files = [
    "nitrogen/generated/ios/ReactNativePharmaScanner-Swift-Cxx-Umbrella.hpp",
    "nitrogen/generated/ios/c++/HybridPharmaScannerSpecSwift.hpp",
  ]

  s.vendored_frameworks = "ios/llama.xcframework"

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "HEADER_SEARCH_PATHS" => [
      "\"$(PODS_TARGET_SRCROOT)/nitrogen/generated/ios\"",
      "\"$(PODS_TARGET_SRCROOT)/nitrogen/generated/shared/c++\"",
    ].join(" "),
    "SWIFT_OBJC_INTEROP_MODE" => "objcxx",
    "OTHER_LDFLAGS" => "-framework VisionKit",
  }

  s.dependency "React-Core"
  s.dependency "NitroModules"
end
