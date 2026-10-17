// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import IOKit.ps

enum MachineModelPolicy {
    static func isPortableMac(powerSourceTypes: [String] = currentPowerSourceTypes()) -> Bool {
        powerSourceTypes.contains(kIOPSInternalBatteryType)
    }

    private static func currentPowerSourceTypes() -> [String] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return []
        }

        return sources.compactMap { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String
        }
    }
}
