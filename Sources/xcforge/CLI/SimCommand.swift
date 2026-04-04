import ArgumentParser
import Foundation
import xcforgeCore

struct Sim: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sim",
        abstract: "Manage iOS simulators (list, boot, shutdown, install, launch, and more).",
        subcommands: [
            SimList.self, SimBoot.self, SimShutdown.self,
            SimInstall.self, SimLaunch.self, SimTerminate.self,
            SimClone.self, SimErase.self, SimDelete.self,
            SimOrientation.self,
        ],
        defaultSubcommand: SimList.self
    )
}

struct SimList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List available iOS simulators with their state and UDID."
    )

    @Option(help: "Filter simulators by name, state, or runtime (e.g. 'iPhone', 'Booted').")
    var filter: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let filter = self.filter
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await SimTools.executeListSims(filter: filter, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(SimRenderer.render(result))
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct SimBoot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "boot",
        abstract: "Boot an iOS simulator by name or UDID."
    )

    @Argument(help: "Simulator name or UDID.")
    var simulator: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await SimTools.executeBootSim(simulator: simulator, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(SimRenderer.render(result))
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct SimShutdown: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shutdown",
        abstract: "Shutdown a running simulator. Use 'all' to shutdown all simulators."
    )

    @Argument(help: "Simulator name or UDID. Use 'all' to shutdown all.")
    var simulator: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await SimTools.executeShutdownSim(simulator: simulator, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(SimRenderer.render(result))
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct SimInstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install an app bundle on a booted simulator. Auto-detects from last build if omitted."
    )

    @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
    var simulator: String?

    @Option(help: "Path to .app bundle. Auto-detected from last build if omitted.")
    var appPath: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let appPath = self.appPath
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await SimTools.executeInstallApp(simulator: simulator, appPath: appPath, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(SimRenderer.render(result))
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct SimLaunch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch an app on a booted simulator. Auto-detects from last build if omitted."
    )

    @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
    var simulator: String?

    @Option(help: "App bundle identifier. Auto-detected from last build if omitted.")
    var bundleId: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let bundleId = self.bundleId
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await SimTools.executeLaunchApp(simulator: simulator, bundleId: bundleId, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(SimRenderer.render(result))
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct SimTerminate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "terminate",
        abstract: "Terminate a running app on a simulator. Auto-detects from last build if omitted."
    )

    @Option(help: "Simulator name or UDID. Auto-detected from booted simulator if omitted.")
    var simulator: String?

    @Option(help: "App bundle identifier. Auto-detected from last build if omitted.")
    var bundleId: String?

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let bundleId = self.bundleId
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await SimTools.executeTerminateApp(simulator: simulator, bundleId: bundleId, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(SimRenderer.render(result))
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct SimClone: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clone",
        abstract: "Clone a simulator to create a snapshot of its current state."
    )

    @Argument(help: "Source simulator name or UDID.")
    var simulator: String

    @Option(help: "Name for the cloned simulator.")
    var name: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let name = self.name
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await SimTools.executeCloneSim(simulator: simulator, name: name, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(SimRenderer.render(result))
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct SimErase: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "erase",
        abstract: "Erase a simulator to factory state. Simulator must be shut down first."
    )

    @Argument(help: "Simulator name, UDID, or 'all' to erase all simulators.")
    var simulator: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await SimTools.executeEraseSim(simulator: simulator, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(SimRenderer.render(result))
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct SimDelete: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Permanently delete a simulator."
    )

    @Argument(help: "Simulator name or UDID to delete.")
    var simulator: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let simulator = self.simulator
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await SimTools.executeDeleteSim(simulator: simulator, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(SimRenderer.render(result))
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}

struct SimOrientation: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "orientation",
        abstract: "Set device orientation via WDA (PORTRAIT, LANDSCAPE, LANDSCAPE_LEFT, LANDSCAPE_RIGHT)."
    )

    @Argument(help: "Target orientation: PORTRAIT, LANDSCAPE, LANDSCAPE_LEFT, LANDSCAPE_RIGHT.")
    var orientation: String

    @Flag(help: "Emit the result as machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let orientation = self.orientation
        let json = self.json

        try runAsync {
            let env = Environment.live
            let result = await SimTools.executeSetOrientation(orientation: orientation, env: env)

            if json {
                print(try WorkflowJSONRenderer.renderJSON(result))
            } else {
                print(SimRenderer.render(result))
            }

            if !result.succeeded {
                throw ExitCode.failure
            }
        }
    }
}
