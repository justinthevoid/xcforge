import CoreGraphics
import CoreImage
import Foundation
import IOSurface
import os

/// Direct Simulator framebuffer capture via CoreSimulator private APIs.
/// Reads the IOSurface backing the Simulator display — no TCC, no background process.
/// ~5-27ms per screenshot (5ms convert + 22ms PNG / 5ms JPEG).
enum CoreSimCapture {

    // MARK: - Xcode Developer Dir (resolved via xcode-select)

    private static let developerDir: String = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}
        return "/Applications/Xcode.app/Contents/Developer"
    }()

    // MARK: - Framework Loading (one-time)

    nonisolated(unsafe) private static let coreSimHandle: UnsafeMutableRawPointer? = {
        // Try system path first, then Xcode-relative
        dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW)
            ?? dlopen("\(developerDir)/Library/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW)
    }()

    nonisolated(unsafe) private static let simKitHandle: UnsafeMutableRawPointer? = {
        dlopen("\(developerDir)/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit", RTLD_NOW)
    }()

    /// CIContext fallback for when direct IOSurface → CGImage fails (lock failure, unexpected format).
    private static let ciContext = CIContext()

    // MARK: - Cached State (avoid re-traversal on every call)

    /// Cached SimServiceContext (~167ms to create).
    nonisolated(unsafe) private static var _serviceContext: NSObject?

    /// Cached descriptor that has the framebufferSurface property.
    /// The IOSurface itself changes on every frame, but the descriptor object is stable.
    nonisolated(unsafe) private static var _cachedDescriptor: NSObject?
    nonisolated(unsafe) private static var _cachedSurfaceSelector: Selector?
    nonisolated(unsafe) private static var _cachedSimulator: String?

    /// Protects all reads/writes to the 4 cached statics above.
    nonisolated(unsafe) private static var _cacheLock = os_unfair_lock()

    /// Whether CoreSimulator frameworks are available.
    static var isAvailable: Bool {
        coreSimHandle != nil
    }

    // MARK: - Public API

    /// Capture framebuffer as CGImage (no encoding, no file I/O).
    /// Synchronous version — only call from non-async contexts or DispatchQueue.
    static func captureImage(simulator: String = "booted") throws -> CGImage {
        guard coreSimHandle != nil else {
            throw CaptureError.frameworkNotFound
        }

        let surface = try getCachedSurface(simulator: simulator)

        // Fast path: direct IOSurface → CGImage (no GPU pipeline)
        if let direct = createCGImageDirect(from: surface) {
            return direct
        }

        // Fallback: CIContext render pipeline (handles unexpected formats, lock failures)
        let ciImage = CIImage(ioSurface: surface)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw CaptureError.conversionFailed
        }
        return cgImage
    }

    /// Pre-initialize the SimServiceContext (~167ms on first call).
    /// Call early to amortize startup cost before the first capture.
    /// Best-effort — errors are logged, not thrown.
    static func warmUp() {
        guard coreSimHandle != nil else { return }
        do {
            _ = try getServiceContext()
        } catch {
            Log.warn("CoreSimCapture warmUp failed: \(error)")
        }
    }

    /// Async-safe version that runs the synchronous ObjC/XPC calls on a dedicated
    /// POSIX thread (DispatchQueue.global), NOT on Swift's Cooperative Thread Pool.
    /// This prevents thread pool exhaustion when CoreSimulator XPC calls block.
    static func captureImageAsync(simulator: String = "booted") async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    let image = try captureImage(simulator: simulator)
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Cached Surface Access

    /// Get the IOSurface, reusing the cached descriptor path when possible.
    private static func getCachedSurface(simulator: String) throws -> IOSurfaceRef {
        // Fast path: reuse cached descriptor
        os_unfair_lock_lock(&_cacheLock)
        let cached: IOSurfaceRef?
        if simulator == _cachedSimulator,
           let descriptor = _cachedDescriptor,
           let surfaceSel = _cachedSurfaceSelector,
           let result = descriptor.perform(surfaceSel)?.takeUnretainedValue()
        {
            let raw = Unmanaged.passUnretained(result).toOpaque()
            let ref = unsafeBitCast(raw, to: IOSurfaceRef.self)
            cached = (IOSurfaceGetWidth(ref) > 0 && IOSurfaceGetHeight(ref) > 0) ? ref : nil
        } else {
            cached = nil
        }
        os_unfair_lock_unlock(&_cacheLock)
        if let cached { return cached }

        // Slow path: full traversal, then cache
        let device = try findDevice(simulator: simulator)
        let (surface, descriptor, surfaceSel) = try findFramebufferSurface(device: device)

        os_unfair_lock_lock(&_cacheLock)
        if simulator == _cachedSimulator,
           let existingDesc = _cachedDescriptor,
           let existingSel = _cachedSurfaceSelector,
           let result = existingDesc.perform(existingSel)?.takeUnretainedValue()
        {
            let raw = Unmanaged.passUnretained(result).toOpaque()
            let ref = unsafeBitCast(raw, to: IOSurfaceRef.self)
            if IOSurfaceGetWidth(ref) > 0 && IOSurfaceGetHeight(ref) > 0 {
                os_unfair_lock_unlock(&_cacheLock)
                return ref
            }
        }
        _cachedDescriptor = descriptor
        _cachedSurfaceSelector = surfaceSel
        _cachedSimulator = simulator
        os_unfair_lock_unlock(&_cacheLock)

        return surface
    }

    // MARK: - Service Context (cached)

    private static func getServiceContext() throws -> NSObject {
        os_unfair_lock_lock(&_cacheLock)
        let cachedCtx = _serviceContext
        os_unfair_lock_unlock(&_cacheLock)
        if let cachedCtx { return cachedCtx }

        guard let ctxClass = NSClassFromString("SimServiceContext") as? NSObject.Type else {
            throw CaptureError.frameworkNotFound
        }

        let devDir = developerDir as NSString
        var error: NSError?
        let ctx: NSObject? = withUnsafeMutablePointer(to: &error) { errPtr in
            let result = (ctxClass as AnyObject).perform(
                sel("sharedServiceContextForDeveloperDir:error:"), with: devDir, with: errPtr)
            return result?.takeUnretainedValue() as? NSObject
        }

        guard let serviceContext = ctx else {
            throw CaptureError.noDevice(
                "SimServiceContext creation failed: \(error?.localizedDescription ?? "unknown")")
        }

        os_unfair_lock_lock(&_cacheLock)
        if let existing = _serviceContext {
            os_unfair_lock_unlock(&_cacheLock)
            return existing
        }
        _serviceContext = serviceContext
        os_unfair_lock_unlock(&_cacheLock)
        return serviceContext
    }

    // MARK: - Device Discovery

    private static func findDevice(simulator: String) throws -> NSObject {
        let serviceContext = try getServiceContext()

        var error: NSError?
        let deviceSet: NSObject? = withUnsafeMutablePointer(to: &error) { errPtr in
            let result = serviceContext.perform(
                sel("defaultDeviceSetWithError:"), with: errPtr)
            return result?.takeUnretainedValue() as? NSObject
        }

        guard let devSet = deviceSet else {
            throw CaptureError.noDevice(
                "Cannot get device set: \(error?.localizedDescription ?? "unknown")")
        }

        guard let devices = devSet.perform(sel("devices"))?.takeUnretainedValue() as? [NSObject]
        else {
            throw CaptureError.noDevice("Cannot enumerate devices")
        }

        if simulator == "booted" {
            for device in devices {
                if let state = device.value(forKey: "state") as? Int, state == 3 {
                    return device
                }
            }
            throw CaptureError.noDevice("No booted simulator found")
        } else {
            for device in devices {
                if let udid = device.perform(sel("UDID"))?.takeUnretainedValue() as? NSUUID,
                    udid.uuidString == simulator
                {
                    return device
                }
            }
            throw CaptureError.noDevice("Simulator \(simulator) not found")
        }
    }

    // MARK: - Framebuffer Access

    /// Find the IOSurface and cache the descriptor + selector for reuse.
    private static func findFramebufferSurface(device: NSObject) throws -> (
        IOSurfaceRef, NSObject, Selector
    ) {
        guard let io = device.value(forKey: "io") as? NSObject else {
            throw CaptureError.noFramebuffer("Cannot access device.io")
        }

        guard let ports = io.perform(sel("ioPorts"))?.takeUnretainedValue() as? [NSObject] else {
            throw CaptureError.noFramebuffer("Cannot access io.ioPorts")
        }

        for port in ports {
            guard
                let descriptor = port.perform(sel("descriptor"))?.takeUnretainedValue() as? NSObject
            else { continue }

            for selName in ["framebufferSurface", "ioSurface"] {
                let s = sel(selName)
                guard descriptor.responds(to: s),
                    let result = descriptor.perform(s)?.takeUnretainedValue()
                else { continue }

                let raw = Unmanaged.passUnretained(result).toOpaque()
                let ref = unsafeBitCast(raw, to: IOSurfaceRef.self)

                if IOSurfaceGetWidth(ref) > 0 && IOSurfaceGetHeight(ref) > 0 {
                    return (ref, descriptor, s)
                }
            }
        }

        throw CaptureError.noFramebuffer("No display port with IOSurface found")
    }

    // MARK: - Direct IOSurface → CGImage (no CIContext)

    /// Convert IOSurface to CGImage using direct pixel access.
    /// Locks the surface for reading, creates a CGImage from the raw BGRA bitmap data.
    /// Returns nil if the surface can't be locked or has an unexpected pixel format.
    private static func createCGImageDirect(from surface: IOSurfaceRef) -> CGImage? {
        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        let bytesPerRow = IOSurfaceGetBytesPerRow(surface)
        let bytesPerElement = IOSurfaceGetBytesPerElement(surface)
        let pixelFormat = IOSurfaceGetPixelFormat(surface)

        // kCVPixelFormatType_32BGRA = 'BGRA' = 0x42475241
        let expectedBGRA: OSType = 0x42475241

        guard width > 0, height > 0, bytesPerElement == 4, pixelFormat == expectedBGRA else {
            Log.warn("CoreSimCapture: unexpected surface format — \(width)×\(height), \(bytesPerElement) bpe, pixelFormat=\(pixelFormat)")
            return nil
        }

        let lockResult = IOSurfaceLock(surface, .readOnly, nil)
        guard lockResult == kIOReturnSuccess else {
            Log.warn("CoreSimCapture: IOSurfaceLock failed (\(lockResult))")
            return nil
        }
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }

        let baseAddress = IOSurfaceGetBaseAddress(surface)
        guard baseAddress != UnsafeMutableRawPointer(bitPattern: 0) else {
            Log.warn("CoreSimCapture: IOSurfaceGetBaseAddress returned null")
            return nil
        }

        // Simulator IOSurface is BGRA 8-bit premultiplied alpha
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Create a copy of the pixel data so the CGImage outlives the surface lock
        guard let data = CFDataCreate(nil, baseAddress.assumingMemoryBound(to: UInt8.self), bytesPerRow * height) else {
            return nil
        }
        guard let provider = CGDataProvider(data: data) else {
            return nil
        }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Helpers

    private static func sel(_ name: String) -> Selector {
        NSSelectorFromString(name)
    }

    enum CaptureError: Error, CustomStringConvertible {
        case frameworkNotFound
        case noDevice(String)
        case noFramebuffer(String)
        case conversionFailed

        var description: String {
            switch self {
            case .frameworkNotFound:
                return "CoreSimulator.framework not found — Xcode not installed?"
            case .noDevice(let msg): return "Device: \(msg)"
            case .noFramebuffer(let msg): return "Framebuffer: \(msg)"
            case .conversionFailed: return "IOSurface → CGImage conversion failed"
            }
        }
    }
}
