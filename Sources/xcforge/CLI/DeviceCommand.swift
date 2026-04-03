import ArgumentParser
import Foundation
import xcforgeCore

struct Device: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "device",
        abstract: "Manage connected physical iOS/iPadOS devices (list, install, launch, and more).",
        subcommands: [
            DeviceList.self, DeviceInfo.self, DeviceInstall.self,
            DeviceUninstall.self, DeviceLaunch.self, DeviceTerminate.self,
            DeviceApps.self,
        ],
        defaultSubcommand: DeviceList.self
    )
}

struct DeviceList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List connected physical devices with their name, UDID, and OS version."
    )

    @Option(help: "Filter devices by name, UDID, or OS version.")
    var filter: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let filter = self.filter
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await DeviceTools.executeListDevices(filter: filter, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(result.message)
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct DeviceInfo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Get detailed information about a connected physical device."
    )

    @Argument(help: "Device name, UDID, or serial number.")
    var device: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let device = self.device
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await DeviceTools.executeDeviceInfo(device: device, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(result.message)
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct DeviceInstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install an .app bundle on a connected physical device."
    )

    @Argument(help: "Path to the .app bundle to install.")
    var appPath: String

    @Option(help: "Device name or UDID.")
    var device: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let appPath = self.appPath
        let device = self.device
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await DeviceTools.executeDeviceInstall(device: device, appPath: appPath, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(result.message)
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct DeviceUninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Uninstall an app from a connected physical device."
    )

    @Argument(help: "Bundle identifier of the app to uninstall.")
    var bundleId: String

    @Option(help: "Device name or UDID.")
    var device: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let bundleId = self.bundleId
        let device = self.device
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await DeviceTools.executeDeviceUninstall(device: device, bundleId: bundleId, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(result.message)
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct DeviceLaunch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch an app on a connected physical device."
    )

    @Argument(help: "Bundle identifier of the app to launch.")
    var bundleId: String

    @Option(help: "Device name or UDID.")
    var device: String

    @Flag(help: "Attach console and wait for app exit.")
    var console = false

    @Flag(inversion: .prefixedNo, help: "Terminate existing instance before launching (default: yes).")
    var terminateExisting = true

    @Option(help: "Console timeout in seconds (default: 30). Only used with --console.")
    var timeout: Int = 30

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let bundleId = self.bundleId
        let device = self.device
        let console = self.console
        let terminateExisting = self.terminateExisting
        let timeout = self.timeout
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await DeviceTools.executeDeviceLaunch(
                device: device,
                bundleId: bundleId,
                console: console,
                terminateExisting: terminateExisting,
                timeout: timeout,
                arguments: nil,
                env: env
            )

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(result.message)
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct DeviceTerminate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "terminate",
        abstract: "Terminate a running process on a connected physical device."
    )

    @Argument(help: "Bundle ID or PID of the process to terminate.")
    var identifier: String

    @Option(help: "Device name or UDID.")
    var device: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let identifier = self.identifier
        let device = self.device
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await DeviceTools.executeDeviceTerminate(device: device, identifier: identifier, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(result.message)
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct DeviceApps: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "List apps installed on a connected physical device."
    )

    @Option(help: "Device name or UDID.")
    var device: String

    @Flag(help: "Include system/built-in apps.")
    var includeSystem = false

    @Option(help: "Filter to a specific bundle ID.")
    var bundleId: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let device = self.device
        let includeSystem = self.includeSystem
        let bundleId = self.bundleId
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await DeviceTools.executeDeviceApps(device: device, includeSystem: includeSystem, bundleId: bundleId, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(result.message)
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}
