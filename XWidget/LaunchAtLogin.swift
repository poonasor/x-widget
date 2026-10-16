import ServiceManagement
import SwiftUI

/// "Start at login" backed by SMAppService, so it always reflects System Settings → Login Items.
/// Nothing is registered until the user turns it on (off by default).
struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Toggle("Start at login", isOn: Binding(get: { isEnabled }, set: setEnabled))
            .onAppear { isEnabled = SMAppService.mainApp.status == .enabled }
        if SMAppService.mainApp.status == .requiresApproval {
            Text("Allow X Widget in System Settings → General → Login Items.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        error = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.error = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
