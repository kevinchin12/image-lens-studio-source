import SwiftUI

struct ProjectWindowContext {
    let locator: ProjectLocator
    let session: WorkspaceSession
}

private struct ProjectWindowContextKey: FocusedValueKey {
    typealias Value = ProjectWindowContext
}

extension FocusedValues {
    var projectWindowContext: ProjectWindowContext? {
        get { self[ProjectWindowContextKey.self] }
        set { self[ProjectWindowContextKey.self] = newValue }
    }
}

struct ProjectFileCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @FocusedValue(\.projectWindowContext) private var projectContext
    let coordinator: ProjectOpenCoordinator

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建项目") {
                Task {
                    guard let locator = await coordinator.createProject() else { return }
                    if !coordinator.focusExistingProjectWindow(locator) {
                        openWindow(id: "project", value: locator)
                    }
                    dismissWindow(id: "project-home")
                }
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("打开项目…") {
                Task {
                    guard let locator = await coordinator.chooseAndOpenProject() else { return }
                    if !coordinator.focusExistingProjectWindow(locator) {
                        openWindow(id: "project", value: locator)
                    }
                    dismissWindow(id: "project-home")
                }
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                guard let projectContext else { return }
                Task {
                    if projectContext.locator.isDraft {
                        guard let newLocator = await coordinator.saveDraft(
                            projectContext.session,
                            locator: projectContext.locator
                        ) else { return }
                        openWindow(id: "project", value: newLocator)
                        dismissWindow(id: "project", value: projectContext.locator)
                    } else {
                        await projectContext.session.flushPendingSave()
                    }
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(projectContext == nil)

            Button("另存为…") {
                guard let projectContext else { return }
                Task {
                    if projectContext.locator.isDraft {
                        guard let newLocator = await coordinator.saveDraft(
                            projectContext.session,
                            locator: projectContext.locator
                        ) else { return }
                        openWindow(id: "project", value: newLocator)
                        dismissWindow(id: "project", value: projectContext.locator)
                        return
                    }
                    guard let newLocator = await coordinator.saveAs(projectContext.session) else { return }
                    if !coordinator.focusExistingProjectWindow(newLocator) {
                        openWindow(id: "project", value: newLocator)
                    }
                    dismissWindow(id: "project", value: projectContext.locator)
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(projectContext == nil)

            Divider()

            Button("导出项目副本…") {
                guard let projectContext else { return }
                Task { await coordinator.exportProjectCopy(projectContext.session) }
            }
            .disabled(projectContext == nil)
        }
    }
}
