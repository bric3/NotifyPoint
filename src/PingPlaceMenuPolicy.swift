// SPDX-License-Identifier: GPL-3.0-only

import Foundation

enum PingPlaceMenuPolicy {
    static func showsRerunDetectionMenuItem(
        explicitFlag: Bool,
        isDebugBuild: Bool
    ) -> Bool {
        explicitFlag || isDebugBuild
    }
}
