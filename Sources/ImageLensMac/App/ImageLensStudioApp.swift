import SwiftUI

@main
struct ImageLensStudioApp: App {
    @NSApplicationDelegateAdaptor(ImageLensApplicationDelegate.self) private var applicationDelegate
    @State private var coordinator = ProjectOpenCoordinator.shared

    var body: some Scene {
        Window("Image Lens Studio", id: "project-home") {
            ProjectHomeView(coordinator: coordinator)
        }
        .defaultSize(width: 820, height: 600)

        WindowGroup("Image Lens Studio", id: "project", for: ProjectLocator.self) { $locator in
            if let locator {
                ProjectWorkspaceHost(locator: locator, coordinator: coordinator)
                    .frame(minWidth: 980, minHeight: 640)
            } else {
                ContentUnavailableView("无法打开项目", systemImage: "exclamationmark.triangle")
            }
        }
        .defaultSize(width: 1320, height: 840)
        .commands {
            ProjectFileCommands(coordinator: coordinator)
        }

        Settings {
            ProviderSettingsView()
        }
    }
}
