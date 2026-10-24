import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--dump") {
    DebugTools.dump()
}

if arguments.contains("--widget-selftest") {
    DebugTools.widgetSelfTest()
}

if let index = arguments.firstIndex(of: "--preview"), index + 1 < arguments.count {
    DebugTools.preview(directory: arguments[index + 1], live: arguments.contains("--live"), cached: arguments.contains("--cached"), monochrome: arguments.contains("--mono"))
}

if let index = arguments.firstIndex(of: "--settings-preview"), index + 1 < arguments.count {
    DebugTools.settingsPreview(path: arguments[index + 1])
}

if let index = arguments.firstIndex(of: "--icon"), index + 1 < arguments.count {
    DebugTools.icon(path: arguments[index + 1])
}

@MainActor
enum AppMain {
    static let delegate = AppDelegate()

    static func run() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
    }
}

MainActor.assumeIsolated { AppMain.run() }
