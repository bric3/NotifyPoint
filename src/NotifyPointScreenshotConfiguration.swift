// SPDX-License-Identifier: GPL-3.0-only

import Foundation

struct NotifyPointScreenshotConfiguration {
    let directory: URL
    let scene: String
    let appearance: String
    let hardware: Bool
    let parentPID: Int32

    static func detect(arguments: [String], launchMode: NotifyPointLaunchMode) throws -> Self? {
        guard let index = arguments.firstIndex(of: "--screenshot-session") else { return nil }
        guard launchMode == .menuPreview, index + 4 < arguments.count,
              ["position", "display"].contains(arguments[index + 2]),
              ["light", "dark"].contains(arguments[index + 3]),
              let parentPID = Int32(arguments[index + 4]), parentPID > 1
        else {
            throw NSError(domain: "NotifyPointScreenshots", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Expected --menu-preview --screenshot-session DIRECTORY position|display light|dark PARENT_PID [--hardware]",
            ])
        }
        return Self(
            directory: URL(fileURLWithPath: arguments[index + 1]),
            scene: arguments[index + 2],
            appearance: arguments[index + 3],
            hardware: arguments.contains("--hardware"),
            parentPID: parentPID
        )
    }

    func showsDisplaySelector(hardwareAvailable: Bool) -> Bool {
        hardware ? hardwareAvailable : scene == "display"
    }
}
