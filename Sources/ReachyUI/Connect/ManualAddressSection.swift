import ReachyDesign
import ReachyKit
import SwiftUI

/// The `Manual` segment. A first-class way in, not a fallback: one robot can appear
/// at several addresses and discovery reaches neither of them on some networks
/// (upstream issue #269).
struct ManualAddressSection: View {
    @Binding var input: String
    var connect: (RobotAddress) -> Void

    private var address: RobotAddress? {
        RobotAddress(parsing: input)
    }

    var body: some View {
        Section {
            TextField(.reachy("host, host:port, or IP"), text: $input)
                .autocorrectionDisabled()
            #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            #endif
            Button(.reachy("Connect")) {
                guard let address else { return }
                connect(address)
            }
            .disabled(address == nil)
        } footer: {
            Label(
                .reachy(
                    // swiftlint:disable:next line_length
                    "The daemon uses unencrypted HTTP without authentication. Connect only on a trusted private network."
                ),
                systemImage: "lock.open.trianglebadge.exclamationmark"
            )
            .foregroundStyle(Tone.warning.style)
        }
    }
}
