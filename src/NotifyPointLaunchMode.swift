// SPDX-License-Identifier: GPL-3.0-only

import Foundation

enum NotifyPointLaunchMode: String, Equatable {
    case full
    case menuPreview
    case smokeTest

    static func detect(arguments: [String], environment: [String: String]) -> NotifyPointLaunchMode {
        if arguments.contains("--menu-preview") {
            return .menuPreview
        }

        if arguments.contains("--smoke-test") {
            return .smokeTest
        }

        if let rawValue = environment["NOTIFYPOINT_MENU_PREVIEW"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           ["1", "true", "yes", "on"].contains(rawValue)
        {
            return .menuPreview
        }

        if let rawValue = environment["NOTIFYPOINT_SMOKE_TEST"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           ["1", "true", "yes", "on"].contains(rawValue)
        {
            return .smokeTest
        }

        return .full
    }
}
