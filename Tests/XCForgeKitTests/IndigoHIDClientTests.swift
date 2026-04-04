import Foundation
import Testing

@testable import XCForgeKit

@Suite("IndigoHIDClient: coordinate normalization and screen dimensions")
struct IndigoHIDClientTests {

  // MARK: - Screen Dimensions

  @Test("iPhone 16 Pro dimensions")
  func iphone16Pro() {
    let dims = IndigoHIDClient.screenDimensions(
      for: "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro")
    #expect(dims.width == 393)
    #expect(dims.height == 852)
    #expect(dims.scale == 3.0)
  }

  @Test("iPhone SE dimensions")
  func iphoneSE() {
    let dims = IndigoHIDClient.screenDimensions(
      for: "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation")
    #expect(dims.width == 375)
    #expect(dims.height == 667)
    #expect(dims.scale == 2.0)
  }

  @Test("iPhone 16 Pro Max dimensions")
  func iphone16ProMax() {
    let dims = IndigoHIDClient.screenDimensions(
      for: "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max")
    #expect(dims.width == 430)
    #expect(dims.height == 932)
    #expect(dims.scale == 3.0)
  }

  @Test("iPhone 15 standard dimensions")
  func iphone15() {
    let dims = IndigoHIDClient.screenDimensions(
      for: "com.apple.CoreSimulator.SimDeviceType.iPhone-15")
    #expect(dims.width == 390)
    #expect(dims.height == 844)
    #expect(dims.scale == 3.0)
  }

  @Test("iPad Pro 12.9 dimensions")
  func iPadPro12() {
    let dims = IndigoHIDClient.screenDimensions(
      for: "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-12-9-inch-6th-generation")
    #expect(dims.width == 1024)
    #expect(dims.height == 1366)
    #expect(dims.scale == 2.0)
  }

  @Test("Unknown device falls back to iPhone 16 Pro")
  func unknownDevice() {
    let dims = IndigoHIDClient.screenDimensions(
      for: "com.apple.CoreSimulator.SimDeviceType.FutureDevice-99")
    #expect(dims.width == 393)
    #expect(dims.height == 852)
    #expect(dims.scale == 3.0)
  }

  // MARK: - Availability

  @Test("isAvailable is a stable bool")
  func availabilityCheck() {
    // Just verify it doesn't crash — actual availability depends on Xcode installation
    let _ = IndigoHIDClient.isAvailable
  }
}
