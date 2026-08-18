import SwiftUI

struct ProjectWorkspaceHost: View {
    let locator: ProjectLocator
    let coordinator: ProjectOpenCoordinator
    @State private var session: WorkspaceSession

    init(locator: ProjectLocator, coordinator: ProjectOpenCoordinator) {
        self.locator = locator
        self.coordinator = coordinator
        _session = State(initialValue: WorkspaceSession(packageURL: locator.url))
    }

    var body: some View {
        WorkspaceRootView(session: session)
            .background(ProjectWindowURLBridge(url: locator.url))
            .focusedSceneValue(
                \.projectWindowContext,
                ProjectWindowContext(locator: locator, session: session)
            )
            .projectOpenRequestRouter(coordinator: coordinator)
            .onChange(of: session.title, initial: true) { _, title in
                if !locator.isDraft {
                    coordinator.recents.register(locator, title: title)
                }
            }
            .onChange(of: session.isReady) { _, isReady in
                guard isReady, !locator.isDraft else { return }
                Task { await coordinator.didOpenProject(locator) }
            }
    }
}

private struct ProjectWindowURLBridge: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { view.window?.representedURL = url }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.representedURL = url }
    }
}
