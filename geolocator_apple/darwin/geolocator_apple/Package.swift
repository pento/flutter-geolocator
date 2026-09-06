// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Resolves BYPASS_PERMISSION_LOCATION_ALWAYS at manifest-evaluation time, in
// priority order:
//   1. The BYPASS_PERMISSION_LOCATION_ALWAYS environment variable.
//   2. Auto-detected an Always usage description from the consuming Flutter app's Info.plist.
//   3. Default to "0".

let env = ProcessInfo.processInfo.environment
let fileManager = FileManager.default

let skippedDirectoryNames: Set<String> = ["Pods", "build", "DerivedData", ".symlinks", ".git"]

func isAppRoot(_ dir: URL) -> Bool {
    guard fileManager.fileExists(atPath: dir.appendingPathComponent("pubspec.yaml").path) else {
        return false
    }
    let iosDir = dir.appendingPathComponent("ios")
    guard let entries = try? fileManager.contentsOfDirectory(atPath: iosDir.path) else {
        return false
    }
    return entries.contains { $0.hasSuffix(".xcodeproj") }
}

func walkUpToAppRoot(from start: URL, maxDepth: Int = 12) -> URL? {
    var dir = start.standardizedFileURL
    for _ in 0..<maxDepth {
        if isAppRoot(dir) { return dir }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { return nil }
        dir = parent
    }
    return nil
}

// Not resolvable for a build launched from within Xcode.app, which runs with
// no usable working directory to walk up from; the env var still works there.
func findAppRoot() -> URL? {
    var starts = [URL(fileURLWithPath: fileManager.currentDirectoryPath)]
    if let pwd = env["PWD"], !pwd.isEmpty {
        starts.append(URL(fileURLWithPath: pwd))
    }
    var visited = Set<String>()
    for start in starts {
        guard visited.insert(start.resolvingSymlinksInPath().path).inserted else { continue }
        if let appRoot = walkUpToAppRoot(from: start) { return appRoot }
    }
    return nil
}

// Enumeration failure returns true, so we don't accidentally bypass.
func appDeclaresLocationAlways(appRoot: URL) -> Bool {
    guard let enumerator = fileManager.enumerator(
        at: appRoot.appendingPathComponent("ios"),
        includingPropertiesForKeys: [.isDirectoryKey]
    ) else { return true }

    for case let url as URL in enumerator {
        let name = url.lastPathComponent
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            if skippedDirectoryNames.contains(name) || name.hasSuffix(".xcworkspace") {
                enumerator.skipDescendants()
            }
            continue
        }
        guard name.hasSuffix(".plist"), name.contains("Info"), !name.contains("Test") else { continue }
        guard let plist = NSDictionary(contentsOf: url) as? [String: Any] else { continue }
        if plist["NSLocationAlwaysAndWhenInUseUsageDescription"] != nil { return true }
        if plist["NSLocationAlwaysUsageDescription"] != nil { return true }
    }
    return false
}

func resolveBypassLocationAlways() -> String {
    if let fromEnv = env["BYPASS_PERMISSION_LOCATION_ALWAYS"]?.trimmingCharacters(in: .whitespaces),
       !fromEnv.isEmpty {
        return fromEnv == "1" ? "1" : "0"
    }
    guard let appRoot = findAppRoot() else { return "0" }
    return appDeclaresLocationAlways(appRoot: appRoot) ? "0" : "1"
}

let bypassLocationAlways = resolveBypassLocationAlways()

let package = Package(
    name: "geolocator_apple",
    platforms: [
        .iOS("11.0"),
        .macOS("10.11")
    ],
    products: [
        .library(name: "geolocator-apple", targets: ["geolocator_apple"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "geolocator_apple",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            publicHeadersPath: "include/geolocator_apple",
            cSettings: [
                .headerSearchPath("include/geolocator_apple"),
                .define("BYPASS_PERMISSION_LOCATION_ALWAYS", to: bypassLocationAlways)
            ]
        )
    ]
)
