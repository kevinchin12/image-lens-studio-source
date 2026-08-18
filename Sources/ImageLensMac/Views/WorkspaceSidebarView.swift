import ImageLensCanvas
import ImageLensCore
import SwiftUI

struct WorkspaceSidebarView: View {
    let session: WorkspaceSession
    let viewportSize: ViewSize
    @Binding var selection: StudioSection?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(StudioSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }

            switch selection {
            case .layers:
                layerList
            case .history:
                runHistory
            case nil:
                EmptyView()
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var layerList: some View {
        if layerRows.isEmpty {
            Section {
                Label("画板还没有内容", systemImage: "square.dashed")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(layerRows) { row in
                    Button {
                        session.focusLayerNode(row.nodeID, viewportSize: viewportSize)
                    } label: {
                        layerRow(row)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("在画布中定位", systemImage: "scope") {
                            session.focusLayerNode(row.nodeID, viewportSize: viewportSize)
                        }
                        Divider()
                        Button("从画布移除", systemImage: "rectangle.badge.minus", role: .destructive) {
                            session.removeCanvasNode(id: row.nodeID)
                        }
                    }
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var runHistory: some View {
        Section {
            if session.runHistoryItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("还没有运行记录", systemImage: "clock.arrow.circlepath")
                    Text("分析图片或生成内容后，会显示在这里。")
                        .font(.caption)
                }
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("运行记录 · \(session.runHistoryItems.count)")
        }

        ForEach(runDaySections) { daySection in
            Section(daySection.title) {
                ForEach(daySection.items) { item in
                    Button {
                        session.selectRun(item.id)
                    } label: {
                        runRow(item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        runContextMenu(item)
                    }
                }
            }
        }
    }

    private var layerRows: [WorkspaceLayerRow] {
        WorkspaceLayerProjection.rows(in: session.workspace)
            .filter { row in
                row.kind != .promptModules && row.kind != .generators
            }
    }

    private func layerRow(_ row: WorkspaceLayerRow) -> some View {
        HStack(spacing: 8) {
            layerThumbnail(row)

            Text(layerTitle(row))
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            session.selectedNodeIDs.contains(row.nodeID)
                ? Color.accentColor.opacity(0.10)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    @ViewBuilder
    private func layerThumbnail(_ row: WorkspaceLayerRow) -> some View {
        if let assetID = row.imageAssetID,
           let asset = session.asset(for: assetID) {
            AssetThumbnailView(session: session, asset: asset, size: 34)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                Image(systemName: layerSystemImage(row.kind))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
            }
        }
    }

    private func layerTitle(_ row: WorkspaceLayerRow) -> String {
        switch row.kind {
        case .sourceImages:
            if let assetID = row.imageAssetID,
               let summary = session.analysisSummary(for: assetID)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty {
                return summary
            }
            return row.title

        case .promptModules:
            return joinedTitle(row.title, row.secondaryDetail)

        case .textBlocks:
            return joinedTitle(row.title, row.secondaryDetail)

        case .recipes, .generators:
            return joinedTitle(row.title, row.secondaryDetail)

        case .generatedImages:
            return row.title
        }
    }

    private func joinedTitle(_ title: String, _ detail: String) -> String {
        guard !detail.isEmpty else { return title }
        return "\(title) · \(detail)"
    }

    private func layerSystemImage(_ kind: WorkspaceLayerKind) -> String {
        switch kind {
        case .sourceImages: "photo"
        case .generatedImages: "sparkles.rectangle.stack"
        case .promptModules: "text.quote"
        case .textBlocks: "note.text"
        case .recipes: "list.bullet.rectangle"
        case .generators: "sparkles"
        }
    }

    private func runRow(_ item: WorkspaceRunItem) -> some View {
        HStack(spacing: 9) {
            runThumbnail(item)

            VStack(alignment: .leading, spacing: 3) {
                Text(runTitle(item))
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(runDetail(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            session.selectedRunID == item.id
                ? Color.accentColor.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    @ViewBuilder
    private func runThumbnail(_ item: WorkspaceRunItem) -> some View {
        if let asset = runAsset(item) {
            AssetThumbnailView(session: session, asset: asset, size: 44)
                .overlay(alignment: .topLeading) {
                    runTypeBadge(item.kind)
                }
                .overlay(alignment: .bottomTrailing) {
                    if item.state != .succeeded {
                        runStateBadge(item.state)
                    }
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                Image(systemName: runTypeIcon(item.kind))
                    .foregroundStyle(runStateColor(item.state))
            }
            .frame(width: 44, height: 44)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            }
        }
    }

    private func runTypeBadge(_ kind: WorkspaceRunKind) -> some View {
        Image(systemName: runTypeIcon(kind))
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.white)
            .padding(3)
            .background(Color.accentColor, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
            }
            .offset(x: -2, y: -2)
    }

    private func runStateBadge(_ state: WorkspaceRunState) -> some View {
        Image(systemName: runStateIcon(state))
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .padding(3)
            .background(runStateColor(state), in: Circle())
            .overlay {
                Circle()
                    .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
            }
            .offset(x: 2, y: 2)
    }

    @ViewBuilder
    private func runContextMenu(_ item: WorkspaceRunItem) -> some View {
        switch item.id {
        case .generation(let generationID):
            if let generation = session.workspace.generations.first(where: { $0.id == generationID }) {
                generationContextMenu(generation)
            }
        case .job:
            if let asset = runAsset(item) {
                if !session.canvasOccurrences(for: asset.id).isEmpty {
                    Button("在画布中定位", systemImage: "scope") {
                        session.focusAssetOnCanvas(asset.id, viewportSize: viewportSize)
                    }
                }
                Button(
                    session.canvasOccurrences(for: asset.id).isEmpty
                        ? "插入画布"
                        : "再插入一个画布实例",
                    systemImage: "plus.rectangle.on.rectangle"
                ) {
                    session.insertAssetOnCanvas(asset.id, viewportSize: viewportSize)
                }
            }
        }
    }

    @ViewBuilder
    private func generationContextMenu(_ generation: GenerationRecord) -> some View {
        if hasCanvasTarget(generation) {
            Button("定位相关结果", systemImage: "scope") {
                session.presentGenerationOnCanvas(generation.id, viewportSize: viewportSize)
            }
        }

        if let asset = firstOutputAsset(for: generation) {
            Button(
                session.canvasOccurrences(for: asset.id).isEmpty
                    ? "插入画布"
                    : "再插入一个画布实例",
                systemImage: "plus.rectangle.on.rectangle"
            ) {
                session.insertAssetOnCanvas(asset.id, viewportSize: viewportSize)
            }

            if !asset.isSavedToLibrary {
                Button("作为素材保留", systemImage: "bookmark") {
                    session.keepAssetInLibrary(asset.id)
                }
            }
        }

        let outputs = session.generationOutputAssets(generation)
        if outputs.count == 1, let output = outputs.first {
            Button("导出结果…", systemImage: "square.and.arrow.up") {
                Task { await AssetExportCoordinator.export(output.id, from: session) }
            }
        } else if !outputs.isEmpty {
            Menu("导出结果", systemImage: "square.and.arrow.up") {
                ForEach(Array(outputs.enumerated()), id: \.element.id) { index, output in
                    Button("结果 \(index + 1)") {
                        Task { await AssetExportCoordinator.export(output.id, from: session) }
                    }
                }
            }
        }
    }

    private func hasCanvasTarget(_ generation: GenerationRecord) -> Bool {
        if let generatorID = generation.generatorID,
           session.generationGroup(for: generatorID) != nil {
            return true
        }
        if let assetID = firstOutputAsset(for: generation)?.id,
           !session.canvasOccurrences(for: assetID).isEmpty {
            return true
        }
        guard let generatorID = generation.generatorID else { return false }
        return session.workspace.canvasNodes.contains { $0.generatorID == generatorID }
    }

    private func firstOutputAsset(for generation: GenerationRecord) -> Asset? {
        generation.outputAssetIDs
            .lazy
            .compactMap(session.asset(for:))
            .first
    }

    private func runTitle(_ item: WorkspaceRunItem) -> String {
        switch item.id {
        case .generation(let generationID):
            let title = session.generationHistoryItems
                .first(where: { $0.id == generationID })?.displayTitle
                ?? (item.kind == .videoGeneration ? "视频生成" : "图片生成")
            return "\(item.kind == .videoGeneration ? "视频生成" : "图片生成") · \(title)"
        case .job:
            return "图片分析 · \(runAsset(item)?.displayName ?? "素材已移除")"
        }
    }

    private func runDetail(_ item: WorkspaceRunItem) -> String {
        let time = item.createdAt.formatted(date: .omitted, time: .shortened)
        var details = [runStateTitle(item)]
        switch item.id {
        case .generation(let generationID):
            if let generation = session.workspace.generations.first(where: { $0.id == generationID }) {
                let unit = item.kind == .videoGeneration ? "个" : "张"
                details.append(
                    generation.outputAssetIDs.isEmpty
                        ? "无结果"
                        : "\(generation.outputAssetIDs.count) \(unit)"
                )
                details.append(generation.aspectRatio)
            }
        case .job:
            if let message = item.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty,
               item.state != .cancelled {
                details.append(message)
            }
        }
        details.append(time)
        return details.joined(separator: " · ")
    }

    private func runAsset(_ item: WorkspaceRunItem) -> Asset? {
        switch item.id {
        case .generation(let generationID):
            guard let generation = session.workspace.generations.first(where: { $0.id == generationID }) else {
                return nil
            }
            return firstOutputAsset(for: generation)
        case .job:
            guard case .asset(let assetID) = item.subject else { return nil }
            return session.asset(for: assetID)
        }
    }

    private var runDaySections: [RunDaySection] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: session.runHistoryItems) {
            calendar.startOfDay(for: $0.createdAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            RunDaySection(
                day: day,
                title: dayTitle(day, calendar: calendar),
                items: grouped[day, default: []]
            )
        }
    }

    private func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        return day.formatted(.dateTime.month().day())
    }

    private func runStateTitle(_ item: WorkspaceRunItem) -> String {
        switch item.state {
        case .queued: "等待中"
        case .running: item.kind == .imageAnalysis ? "分析中" : "生成中"
        case .partial: "部分完成"
        case .succeeded: "完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }

    private func runStateIcon(_ state: WorkspaceRunState) -> String {
        switch state {
        case .queued: "clock"
        case .running: "circle.dotted"
        case .partial: "circle.lefthalf.filled"
        case .succeeded: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        case .cancelled: "xmark.circle"
        }
    }

    private func runStateColor(_ state: WorkspaceRunState) -> Color {
        switch state {
        case .queued: .secondary
        case .running: .blue
        case .partial: .orange
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }

    private func runTypeIcon(_ kind: WorkspaceRunKind) -> String {
        switch kind {
        case .imageAnalysis: "viewfinder"
        case .imageGeneration: "sparkles"
        case .videoGeneration: "film"
        case .thumbnail: "photo.badge.arrow.down"
        }
    }
}

private struct RunDaySection: Identifiable {
    let day: Date
    let title: String
    let items: [WorkspaceRunItem]

    var id: Date { day }
}
