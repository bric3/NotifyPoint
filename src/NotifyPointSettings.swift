// SPDX-License-Identifier: GPL-3.0-only

import Foundation

enum NotifyPointSettingsKey: String, CaseIterable {
    case isMenuBarIconHidden
    case debugMode
    case showRerunDetectionMenuItem
    case notificationPosition
    case notificationDisplayTarget
}

enum NotifyPointSettingsSource: Equatable {
    static let defaultSmokeTestFile = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("NotifyPoint.smoke-test.json")

    case standard
    case suite(String)
    case file(URL)

    var suiteName: String? {
        switch self {
        case .standard, .file:
            return nil
        case let .suite(name):
            return name
        }
    }

    var fileURL: URL? {
        switch self {
        case let .file(url):
            return url
        case .standard, .suite:
            return nil
        }
    }

    static func detect(
        arguments: [String],
        environment: [String: String],
        launchMode: NotifyPointLaunchMode
    ) -> NotifyPointSettingsSource {
        if let url = explicitFileURL(arguments: arguments) {
            return .file(url)
        }

        if let filePath = environment["NOTIFYPOINT_SETTINGS_FILE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !filePath.isEmpty
        {
            return .file(URL(fileURLWithPath: filePath))
        }

        if let suiteName = explicitSuiteName(arguments: arguments), !suiteName.isEmpty {
            return .suite(suiteName)
        }

        if let suiteName = environment["NOTIFYPOINT_SETTINGS_SUITE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !suiteName.isEmpty
        {
            return .suite(suiteName)
        }

        if launchMode == .smokeTest {
            return .file(defaultSmokeTestFile)
        }

        return .standard
    }

    private static func explicitSuiteName(arguments: [String]) -> String? {
        if let index = arguments.firstIndex(of: "--settings-suite"), index + 1 < arguments.count {
            return arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for argument in arguments where argument.hasPrefix("--settings-suite=") {
            return String(argument.dropFirst("--settings-suite=".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private static func explicitFileURL(arguments: [String]) -> URL? {
        if let index = arguments.firstIndex(of: "--settings-file"), index + 1 < arguments.count {
            let path = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }

        for argument in arguments where argument.hasPrefix("--settings-file=") {
            let path = String(argument.dropFirst("--settings-file=".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }
}

struct NotifyPointRuntimeConfiguration: Equatable {
    let launchMode: NotifyPointLaunchMode
    let settingsSource: NotifyPointSettingsSource

    static func detect(arguments: [String], environment: [String: String]) -> NotifyPointRuntimeConfiguration {
        let launchMode = NotifyPointLaunchMode.detect(arguments: arguments, environment: environment)
        let settingsSource = NotifyPointSettingsSource.detect(
            arguments: arguments,
            environment: environment,
            launchMode: launchMode
        )
        return NotifyPointRuntimeConfiguration(
            launchMode: launchMode,
            settingsSource: settingsSource
        )
    }
}

private struct NotifyPointSettingsPayload: Codable {
    var isMenuBarIconHidden: Bool?
    var debugMode: Bool?
    var showRerunDetectionMenuItem: Bool?
    var notificationPosition: String?
    var notificationDisplayTarget: String?

    func value(for key: NotifyPointSettingsKey) -> Any? {
        switch key {
        case .isMenuBarIconHidden:
            return isMenuBarIconHidden
        case .debugMode:
            return debugMode
        case .showRerunDetectionMenuItem:
            return showRerunDetectionMenuItem
        case .notificationPosition:
            return notificationPosition
        case .notificationDisplayTarget:
            return notificationDisplayTarget
        }
    }

    mutating func set(_ value: Any?, for key: NotifyPointSettingsKey) {
        switch key {
        case .isMenuBarIconHidden:
            isMenuBarIconHidden = value as? Bool
        case .debugMode:
            debugMode = value as? Bool
        case .showRerunDetectionMenuItem:
            showRerunDetectionMenuItem = value as? Bool
        case .notificationPosition:
            notificationPosition = value as? String
        case .notificationDisplayTarget:
            notificationDisplayTarget = value as? String
        }
    }
}

final class NotifyPointSettings {
    let source: NotifyPointSettingsSource
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(source: NotifyPointSettingsSource) {
        self.source = source
        switch source {
        case .standard:
            defaults = .standard
        case let .suite(name):
            defaults = UserDefaults(suiteName: name) ?? .standard
        case .file:
            defaults = .standard
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var suiteName: String? {
        source.suiteName
    }

    var fileURL: URL? {
        source.fileURL
    }

    func bool(forKey key: NotifyPointSettingsKey) -> Bool {
        switch source {
        case .file:
            return (payload()?.value(for: key) as? Bool) ?? false
        case .standard, .suite:
            return defaults.bool(forKey: key.rawValue)
        }
    }

    func object(forKey key: NotifyPointSettingsKey) -> Any? {
        switch source {
        case .file:
            return payload()?.value(for: key)
        case .standard, .suite:
            return defaults.object(forKey: key.rawValue)
        }
    }

    func string(forKey key: NotifyPointSettingsKey) -> String? {
        switch source {
        case .file:
            return payload()?.value(for: key) as? String
        case .standard, .suite:
            return defaults.string(forKey: key.rawValue)
        }
    }

    func set(_ value: Any?, forKey key: NotifyPointSettingsKey) {
        switch source {
        case .file:
            var currentPayload = payload() ?? NotifyPointSettingsPayload()
            currentPayload.set(value, for: key)
            write(payload: currentPayload)
        case .standard, .suite:
            defaults.set(value, forKey: key.rawValue)
        }
    }

    private func payload() -> NotifyPointSettingsPayload? {
        guard case let .file(url) = source else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(NotifyPointSettingsPayload.self, from: data)
    }

    private func write(payload: NotifyPointSettingsPayload) {
        guard case let .file(url) = source else { return }
        do {
            let data = try encoder.encode(payload)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Writing smoke-test settings should not crash the app.
        }
    }
}
