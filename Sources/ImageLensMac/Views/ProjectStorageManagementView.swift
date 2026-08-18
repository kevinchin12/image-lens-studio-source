import AppKit
import SwiftUI

struct ProjectStorageManagementView: View {
    let session: WorkspaceSession
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: ProjectStorageSnapshot?
    @State private var isLoading = false
    @State private var isCleaning = false
    @State private var isCleanupConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("项目存储管理")
                        .font(.title2.weight(.semibold))
                    Text("查看项目占用，并清理当前未在画布、素材库或节点引用中使用的生成结果。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .disabled(isCleaning)
            }

            if let snapshot {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                    storageRow("项目总占用", bytes: snapshot.usage.totalBytes)
                    storageRow("原始素材", bytes: snapshot.usage.originalAssetBytes)
                    storageRow("生成结果", bytes: snapshot.usage.derivedAssetBytes)
                    storageRow("缩略图", bytes: snapshot.usage.thumbnailBytes)
                    storageRow("项目记录与其他文件", bytes: snapshot.usage.otherBytes)
                }

                Divider()

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: snapshot.reclaimableBytes > 0 ? "trash" : "checkmark.circle")
                        .foregroundStyle(snapshot.reclaimableBytes > 0 ? .orange : .green)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            snapshot.reclaimableBytes > 0
                                ? "可释放 \(formatted(snapshot.reclaimableBytes))"
                                : "没有可清理内容"
                        )
                        .font(.headline)
                        Text(
                            snapshot.reclaimableBytes > 0
                                ? "包含 \(snapshot.removableAssetCount) 个当前未使用的生成结果和 \(snapshot.removableFileCount) 个文件。运行记录和提示词仍会保留，但这些媒体将无法再从历史中打开。"
                                : "仍在画布、素材库、参考连接、分析或提示词证据中使用的内容都会保留。"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在检查项目文件…")
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            }

            Text("从画布移除节点不会自动删除项目中的素材或生成历史。存储清理不可撤销，也不会进入画布的撤销记录。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("在 Finder 中显示项目") {
                    NSWorkspace.shared.activateFileViewerSelecting([session.packageURL])
                }
                Spacer()
                Button("重新扫描") { Task { await loadSnapshot() } }
                    .disabled(isLoading || isCleaning)
                Button("清理未使用的生成结果…", role: .destructive) {
                    isCleanupConfirmationPresented = true
                }
                .disabled(
                    snapshot?.reclaimableBytes == 0
                        || snapshot == nil
                        || isLoading
                        || isCleaning
                        || session.hasActiveFileProducingTasks
                )
            }
        }
        .padding(22)
        .frame(width: 560)
        .task { await loadSnapshot() }
        .confirmationDialog(
            "永久清理项目文件？",
            isPresented: $isCleanupConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                "清理并释放 \(formatted(snapshot?.reclaimableBytes ?? 0))",
                role: .destructive
            ) {
                Task { await performCleanup() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将永久删除当前未使用的生成媒体。运行记录和提示词会保留，但被清理的结果无法恢复。")
        }
    }

    private func storageRow(_ label: String, bytes: Int64) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(formatted(bytes)).monospacedDigit()
        }
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func loadSnapshot() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await session.inspectProjectStorage()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    private func performCleanup() async {
        isCleaning = true
        defer { isCleaning = false }
        do {
            snapshot = try await session.cleanUnusedGeneratedResults()
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
}
