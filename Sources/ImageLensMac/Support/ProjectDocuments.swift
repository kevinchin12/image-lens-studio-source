import AppKit
import Foundation
import ImageLensCore
import ImageLensPersistence
import Observation
import UniformTypeIdentifiers

extension UTType {
    static let imageLensProject = UTType(
        exportedAs: "com.jiawenqin.imagelensstudio.project",
        conformingTo: .package
    )
}

struct ProjectLocator: Codable, Hashable, Identifiable, Sendable {
    let path: String

    init(url: URL) {
        path = url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var displayName: String { url.deletingPathExtension().lastPathComponent }

    static var draftsDirectoryURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Image Lens Studio", isDirectory: true)
            .appendingPathComponent("Drafts", isDirectory: true)
    }

    var isDraft: Bool {
        let draftsPath = Self.draftsDirectoryURL.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(draftsPath)
    }
}

struct DraftProject: Identifiable, Hashable, Sendable {
    let locator: ProjectLocator
    let modifiedAt: Date

    var id: String { locator.id }
}

struct RecentProject: Codable, Hashable, Identifiable, Sendable {
    let locator: ProjectLocator
    var title: String
    var lastOpenedAt: Date

    var id: String { locator.id }
    var isAvailable: Bool { FileManager.default.fileExists(atPath: locator.path) }
}

@MainActor
@Observable
final class RecentProjectStore {
    private static let defaultsKey = "recentImageLensProjects.v1"
    private(set) var projects: [RecentProject] = []

    init(defaults: UserDefaults = .standard) {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([RecentProject].self, from: data) else {
            return
        }
        projects = decoded
    }

    func register(_ locator: ProjectLocator, title: String? = nil) {
        projects.removeAll { $0.locator == locator }
        projects.insert(
            RecentProject(
                locator: locator,
                title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? locator.displayName,
                lastOpenedAt: .now
            ),
            at: 0
        )
        if projects.count > 20 {
            projects.removeLast(projects.count - 20)
        }
        persist()
    }

    func remove(_ locator: ProjectLocator) {
        projects.removeAll { $0.locator == locator }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

@MainActor
@Observable
final class ProjectOpenCoordinator {
    static let shared = ProjectOpenCoordinator()

    let recents = RecentProjectStore()
    private let repository = WorkspacePackageRepository()
    private(set) var pendingLocators: [ProjectLocator] = []
    private(set) var requestVersion = 0
    var errorMessage: String?
    private(set) var drafts: [DraftProject] = []
    private var pendingDraftCleanup: [ProjectLocator: ProjectLocator] = [:]

    init() {
        refreshDrafts()
    }

    var legacyProjectURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Image Lens Studio", isDirectory: true)
            .appendingPathComponent("Default.imagelens", isDirectory: true)
    }

    var hasLegacyProject: Bool {
        FileManager.default.fileExists(
            atPath: WorkspacePackageLayout(packageURL: legacyProjectURL).manifestURL.path
        )
    }

    func createProject() async -> ProjectLocator? {
        let url = ProjectLocator.draftsDirectoryURL.appendingPathComponent(
            "Untitled-\(UUID().uuidString.lowercased()).imagelens",
            isDirectory: true
        )
        let workspace = Workspace(title: "未命名项目")
        do {
            try await repository.createPackage(workspace, at: url)
            let locator = ProjectLocator(url: url)
            refreshDrafts()
            return locator
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func chooseAndOpenProject() async -> ProjectLocator? {
        guard let url = chooseExistingProjectURL() else { return nil }
        return await validateProject(url)
    }

    func validateProject(_ url: URL) async -> ProjectLocator? {
        let locator = ProjectLocator(url: url)
        do {
            let workspace = try await repository.load(from: locator.url)
            if !locator.isDraft {
                recents.register(locator, title: workspace.title)
            }
            return locator
        } catch {
            recents.remove(locator)
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func openRecent(_ project: RecentProject) async -> ProjectLocator? {
        guard project.isAvailable else {
            errorMessage = "找不到“\(project.title)”。它可能已被移动或删除。"
            return nil
        }
        return await validateProject(project.locator.url)
    }

    func saveAs(_ session: WorkspaceSession) async -> ProjectLocator? {
        guard let destinationURL = chooseNewProjectURL(suggestedName: session.title) else { return nil }
        guard ProjectLocator(url: destinationURL) != ProjectLocator(url: session.packageURL) else {
            errorMessage = "“另存为”需要选择另一个名称或位置。直接保存当前项目请使用 Command–S。"
            return nil
        }
        do {
            let clonedWorkspace = try await session.cloneProject(to: destinationURL)
            let locator = ProjectLocator(url: destinationURL)
            recents.register(locator, title: clonedWorkspace.title)
            return locator
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func saveDraft(_ session: WorkspaceSession, locator: ProjectLocator) async -> ProjectLocator? {
        guard locator.isDraft else {
            await session.flushPendingSave()
            return nil
        }
        guard !session.hasActiveFileProducingTasks else {
            errorMessage = "仍有素材导入、图片分析或图片生成任务正在进行，请完成后再保存项目。"
            return nil
        }
        guard let destinationURL = chooseNewProjectURL(suggestedName: "未命名项目") else { return nil }
        do {
            let savedWorkspace = try await session.finalizeDraftProject(to: destinationURL)
            let destination = ProjectLocator(url: destinationURL)
            recents.register(destination, title: savedWorkspace.title)
            pendingDraftCleanup[destination] = locator
            return destination
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func didOpenProject(_ locator: ProjectLocator) async {
        guard let draftLocator = pendingDraftCleanup.removeValue(forKey: locator) else { return }
        try? await repository.removePackage(at: draftLocator.url)
        refreshDrafts()
    }

    func discardDraft(_ draft: DraftProject) async {
        do {
            try await repository.removePackage(at: draft.locator.url)
            refreshDrafts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshDrafts() {
        let directoryURL = ProjectLocator.draftsDirectoryURL
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            drafts = []
            return
        }
        drafts = urls.compactMap { url in
            guard url.pathExtension.lowercased() == "imagelens",
                  FileManager.default.fileExists(
                    atPath: WorkspacePackageLayout(packageURL: url).manifestURL.path
                  ) else { return nil }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return DraftProject(
                locator: ProjectLocator(url: url),
                modifiedAt: values?.contentModificationDate ?? .distantPast
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func exportProjectCopy(_ session: WorkspaceSession) async {
        guard let destinationURL = chooseNewProjectURL(suggestedName: "\(session.title) 副本") else { return }
        guard ProjectLocator(url: destinationURL) != ProjectLocator(url: session.packageURL) else {
            errorMessage = "项目副本需要保存到另一个名称或位置。"
            return
        }
        do {
            try await session.exportProjectCopy(to: destinationURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func migrateLegacyProject() async -> ProjectLocator? {
        guard hasLegacyProject,
              let destinationURL = chooseNewProjectURL(suggestedName: "我的画板") else { return nil }
        do {
            var workspace = try await repository.load(from: legacyProjectURL)
            workspace.title = destinationURL.deletingPathExtension().lastPathComponent
            workspace.updatedAt = .now
            try await repository.clonePackage(
                from: legacyProjectURL,
                to: destinationURL,
                workspace: workspace
            )
            let locator = ProjectLocator(url: destinationURL)
            recents.register(locator, title: workspace.title)
            return locator
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func requestOpen(_ locator: ProjectLocator, title: String? = nil) {
        if !locator.isDraft {
            recents.register(locator, title: title)
        }
        guard !pendingLocators.contains(locator) else { return }
        pendingLocators.append(locator)
        requestVersion += 1
    }

    /// SwiftUI's value WindowGroup can create another occurrence for the same
    /// value. Project windows publish their canonical package URL to NSWindow,
    /// allowing every open entry point to focus the existing editor instead.
    func focusExistingProjectWindow(_ locator: ProjectLocator) -> Bool {
        guard let window = NSApp.windows.first(where: { window in
            guard let representedURL = window.representedURL else { return false }
            return ProjectLocator(url: representedURL) == locator
        }) else { return false }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func drainOpenRequests() -> [ProjectLocator] {
        defer { pendingLocators.removeAll() }
        return pendingLocators
    }

    private func chooseNewProjectURL(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "保存 Image Lens 项目"
        panel.prompt = "保存"
        panel.allowedContentTypes = [.imageLensProject]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(suggestedName).imagelens"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.pathExtension.lowercased() == "imagelens"
            ? url
            : url.appendingPathExtension("imagelens")
    }

    private func chooseExistingProjectURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "打开 Image Lens 项目"
        panel.prompt = "打开"
        panel.allowedContentTypes = [.imageLensProject]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
final class ImageLensApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0, isDirectory: true) }
        Task { @MainActor in
            for url in urls where url.pathExtension.lowercased() == "imagelens" {
                if let locator = await ProjectOpenCoordinator.shared.validateProject(url) {
                    ProjectOpenCoordinator.shared.requestOpen(locator)
                }
            }
            sender.reply(toOpenOrPrint: .success)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
