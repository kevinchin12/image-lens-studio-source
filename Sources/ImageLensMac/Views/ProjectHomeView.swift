import SwiftUI

struct ProjectHomeView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    let coordinator: ProjectOpenCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            actionRow
            if !coordinator.drafts.isEmpty {
                draftProjects
            }
            recentProjects
            Spacer(minLength: 0)
        }
        .padding(36)
        .frame(minWidth: 760, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .projectOpenRequestRouter(coordinator: coordinator)
        .task { coordinator.refreshDrafts() }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { if !$0 { coordinator.errorMessage = nil } }
            )
        ) {
            Button("好") { coordinator.errorMessage = nil }
        } message: {
            Text(coordinator.errorMessage ?? "发生未知错误")
        }
    }

    private var draftProjects: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("未保存画板")
                .font(.headline)

            ForEach(coordinator.drafts) { draft in
                Button {
                    openProject(draft.locator)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.badge.clock")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("未命名项目")
                                .fontWeight(.medium)
                            Text("关闭前的内容已自动保留")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(draft.modifiedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Image Lens Studio")
                .font(.system(size: 30, weight: .semibold))
            Text("每个项目是一块独立画板，素材、节点和生成记录都保存在项目文件中。")
                .foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    if let locator = await coordinator.createProject() {
                        openProject(locator)
                    }
                }
            } label: {
                Label("新建项目", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                Task {
                    if let locator = await coordinator.chooseAndOpenProject() {
                        openProject(locator)
                    }
                }
            } label: {
                Label("打开项目", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if coordinator.hasLegacyProject {
                Button {
                    Task {
                        if let locator = await coordinator.migrateLegacyProject() {
                            openProject(locator)
                        }
                    }
                } label: {
                    Label("迁移原画板", systemImage: "arrow.up.doc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("复制旧的默认画板为独立项目；原画板仍会保留")
            }
        }
    }

    private var recentProjects: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近项目")
                .font(.headline)

            if coordinator.recents.projects.isEmpty {
                ContentUnavailableView(
                    "还没有项目",
                    systemImage: "rectangle.stack",
                    description: Text("新建后会直接进入画布，第一次保存时再选择名称和位置。")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List(coordinator.recents.projects) { project in
                    Button {
                        Task {
                            if let locator = await coordinator.openRecent(project) {
                                openProject(locator)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: project.isAvailable ? "square.grid.2x2" : "questionmark.folder")
                                .font(.title3)
                                .foregroundStyle(project.isAvailable ? Color.accentColor : .secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.title)
                                    .fontWeight(.medium)
                                Text(project.locator.url.deletingLastPathComponent().path(percentEncoded: false))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(project.lastOpenedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!project.isAvailable)
                    .contextMenu {
                        Button("从最近项目移除") {
                            coordinator.recents.remove(project.locator)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func openProject(_ locator: ProjectLocator) {
        if !coordinator.focusExistingProjectWindow(locator) {
            openWindow(id: "project", value: locator)
        }
        dismissWindow(id: "project-home")
    }
}

private struct ProjectOpenRequestRouter: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    let coordinator: ProjectOpenCoordinator

    func body(content: Content) -> some View {
        content.task(id: coordinator.requestVersion) {
            let locators = coordinator.drainOpenRequests()
            for locator in locators {
                guard !coordinator.focusExistingProjectWindow(locator) else { continue }
                openWindow(id: "project", value: locator)
            }
            if !locators.isEmpty {
                dismissWindow(id: "project-home")
            }
        }
    }
}

extension View {
    func projectOpenRequestRouter(coordinator: ProjectOpenCoordinator) -> some View {
        modifier(ProjectOpenRequestRouter(coordinator: coordinator))
    }
}
