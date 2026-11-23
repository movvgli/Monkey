import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct LocalHistoryView: View {
    @Environment(LocalHistoryStore.self) private var history
    @State private var showsImporter = false
    let kind: HistoryKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WookeyPageMetrics.headerSpacing) {
                header
                if kind == .images {
                    ImageDropTarget(history: history)
                        .frame(height: 146)
                }
                if let error = history.errors[kind] {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                let entries = history.entries(kind)
                if entries.isEmpty {
                    ContentUnavailableView {
                        WookeyEmptyStateLabel(
                            title: kind == .clipboard ? "클립보드 기록이 없습니다" : "보관한 이미지가 없습니다",
                            symbol: kind.symbol
                        )
                    } description: {
                        Text(emptyDescription)
                    }
                    .frame(maxWidth: .infinity, minHeight: 175)
                } else if kind == .clipboard {
                    PlainPanel {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                if entry.id != entries.first?.id { Divider() }
                                clipboardRow(entry)
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(entries) { entry in
                            imageCard(entry)
                        }
                    }
                }
            }
            .padding(WookeyPageMetrics.padding)
            .frame(maxWidth: WookeyPageMetrics.maximumWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(kind.title)
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if !history.importImage(at: url) { history.showImageImportError() }
                }
            case .failure:
                history.showImageImportError()
            }
        }
    }

    private var emptyDescription: String {
        if kind == .images { return "위에 사진을 놓거나 ‘이미지 추가’를 사용하세요." }
        return history.recordsClipboard
            ? "텍스트, 이미지 또는 파일을 복사하면 여기에 표시됩니다."
            : "설정의 보관 기간 탭에서 클립보드 기록을 켤 수 있습니다."
    }

    private var header: some View {
        let subtitle = kind == .clipboard
            ? "최근 복사한 내용을 찾아 다시 복사합니다."
            : "보관한 사진을 모아 보고 열 수 있습니다."
        return WookeyPageHeader(title: kind.title, subtitle: subtitle) {
            if kind == .images {
                Button("이미지 추가", wookeyIcon: "plus") { showsImporter = true }
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .controlSize(.large)
            }
        }
    }

    private func clipboardRow(_ entry: LocalHistoryStore.Entry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).lineLimit(2)
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("다시 복사", systemImage: "doc.on.doc") { history.restoreClipboard(entry) }
            removeButton(entry)
        }
        .padding(.vertical, 8)
    }

    private func imageCard(_ entry: LocalHistoryStore.Entry) -> some View {
        let url = history.fileURL(for: entry, kind: .images)
        return PlainPanel {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    if !NSWorkspace.shared.open(url) { history.showImageImportError() }
                } label: {
                    HistoryImageThumbnail(url: url)
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(entry.name) 열기")
                HStack(spacing: 5) {
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(entry.name)
                    Spacer(minLength: 0)
                    removeButton(entry)
                }
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func removeButton(_ entry: LocalHistoryStore.Entry) -> some View {
        Button("삭제", wookeyIcon: "trash") { history.remove(entry, kind: kind) }
            .labelStyle(.iconOnly)
            .buttonStyle(WookeyGlossyButtonStyle(tint: .neutral, iconOnly: true))
            .controlSize(.small)
    }
}

private struct HistoryImageThumbnail: View {
    let url: URL
    @State private var thumbnail: CGImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            thumbnail = await Task.detached(priority: .utility) {
                historyImageThumbnail(at: url, maxPixelSize: 360)
            }.value
        }
    }
}

func historyImageThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

struct ImageDropSurface: View {
    @Environment(\.wookeyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var biteStage: BiteStage = .idle
    let feedback: ImageDropFeedback
    let floating: Bool

    private enum BiteStage { case idle, offered, swallowed, saved }

    private let wookeySize: CGFloat = 100
    private let mouthOffset = CGSize(width: -10, height: -9)

    private var mouthIsOpen: Bool { feedback.isTargeted || biteStage == .offered }
    private var isSaved: Bool { biteStage == .saved }

    var body: some View {
        VStack(spacing: 4) {
            character
            message
            if !floating {
                Text("다른 앱에서 사진을 끌다가 두 번 흔들면 드롭박스가 열려요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WookeyGlossyPanel(radius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(feedback.isTargeted ? WookeyTheme.banana : .clear, lineWidth: 2)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: feedback.isTargeted)
        .task(id: feedback.receipt?.id) {
            guard feedback.receipt != nil else { return }
            await playBite()
        }
    }

    private var character: some View {
        ZStack {
            Circle()
                .fill(WookeyTheme.banana.opacity(feedback.isTargeted ? 0.5 : 0.22))
                .frame(width: 72, height: 72)
                .blur(radius: 6)
            ZStack {
                Image("ImageShelfPhotoWookey", bundle: wookeyAssetBundle)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                Ellipse()
                    .fill(WookeyTheme.cocoa)
                    .frame(width: 8, height: 7)
                    .rotationEffect(.degrees(14))
                    .offset(mouthOffset)
                    .opacity(mouthIsOpen ? 1 : 0)
            }
            .frame(width: wookeySize, height: wookeySize)
            .scaleEffect(reduceMotion ? 1 : wookeyScale)

            if !reduceMotion, let receipt = feedback.receipt {
                photoCard(receipt.photo)
                    .rotationEffect(.degrees(biteStage == .offered ? -14 : 0))
                    .scaleEffect(biteStage == .offered ? 1 : 0.13)
                    .offset(biteStage == .offered ? CGSize(width: -46, height: 12) : mouthOffset)
                    .opacity(biteStage == .offered ? 1 : 0)
            }
        }
        .frame(width: 124, height: 90)
        .accessibilityHidden(true)
    }

    private var wookeyScale: CGFloat {
        if biteStage == .swallowed { return 0.91 }
        if mouthIsOpen || isSaved { return 1.06 }
        return 1
    }

    private var message: some View {
        let title = if isSaved { "이미지를 보관했어요" }
        else if feedback.isReceiving { "이미지를 가져오는 중…" }
        else if feedback.isTargeted { "여기에 놓으세요" }
        else { "우키에게 사진을 주세요" }
        return HStack(spacing: 5) {
            if isSaved { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
            Text(title)
        }
        .font(.system(size: floating ? 12 : 15, weight: .semibold, design: .rounded))
        .foregroundStyle(theme.accent)
        .lineLimit(1)
    }

    private func photoCard(_ photo: CGImage?) -> some View {
        Group {
            if let photo {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(theme.accent)
            }
        }
        .frame(width: 28, height: 24)
        .background(theme.canvas)
        .clipShape(.rect(cornerRadius: 3))
        .padding(3)
        .background(.white, in: .rect(cornerRadius: 5))
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }

    @MainActor
    private func playBite() async {
        do {
            if !reduceMotion {
                biteStage = .offered
                try await Task.sleep(for: .milliseconds(85))
                withAnimation(.easeIn(duration: 0.22)) { biteStage = .swallowed }
                try await Task.sleep(for: .milliseconds(230))
            }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.35)) { biteStage = .saved }
            try await Task.sleep(for: .milliseconds(625))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { biteStage = .idle }
        } catch {
            // A more recent drop restarts the animation.
        }
    }
}

struct HistorySettingsView: View {
    @Environment(LocalHistoryStore.self) private var history

    var body: some View {
        WookeySection(
            title: "보관 기간",
            detail: "기록은 이 Mac에만 저장되며, 보관 기간이 지나면 자동으로 삭제됩니다."
        ) {
            ForEach(HistoryKind.allCases, id: \.self) { kind in
                PlainPanel {
                    HStack(alignment: .top, spacing: 12) {
                        WookeyActionIcon(symbol: kind.symbol, tint: WookeyActionTint(symbol: kind.symbol), size: 26)
                        VStack(alignment: .leading, spacing: 12) {
                            historyHeader(for: kind)
                            Divider()
                            HistoryRetentionControls(kind: kind)
                            if let error = history.errors[kind] {
                                WookeyControlLabel(title: error, symbol: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    private func historyHeader(for kind: HistoryKind) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(description(for: kind))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if kind == .clipboard {
                Toggle("클립보드 기록", isOn: Binding(
                    get: { history.recordsClipboard },
                    set: { history.setRecordsClipboard($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(WookeyTheme.banana)
            }
        }
    }

    private func description(for kind: HistoryKind) -> String {
        switch kind {
        case .clipboard:
            history.recordsClipboard
                ? "복사한 텍스트, 이미지, 파일을 기록합니다."
                : "새로 복사한 내용은 기록하지 않습니다."
        case .images:
            "이미지 보관함에 추가한 사진을 저장합니다."
        }
    }
}

private struct HistoryRetentionControls: View {
    @Environment(LocalHistoryStore.self) private var history
    @State private var draft = HistoryRetention()
    @State private var amount = ""
    let kind: HistoryKind

    var body: some View {
        let saved = history.retention(kind)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("보관 기간")
                Spacer()
                Picker("\(kind.title) 보관 기간", selection: $draft.period) {
                    ForEach(HistoryRetention.Period.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            if draft.period == .custom {
                HStack {
                    Text("직접 설정한 기간")
                    Spacer()
                    TextField("기간", text: $amount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .accessibilityLabel("\(kind.title) 보관 기간 값")
                    Picker("기간 단위", selection: $draft.unit) {
                        ForEach(HistoryRetention.Unit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if hasChanges(from: saved) {
                HStack(spacing: 12) {
                    if proposedRetention == nil {
                        Text("1 이상의 정수를 입력하세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let seconds = proposedRetention?.seconds,
                              seconds < (saved.seconds ?? .infinity) {
                        Text("새 보관 기간이 지난 기록은 적용 즉시 삭제됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("적용", wookeyIcon: "checkmark.circle.fill") {
                        if let proposedRetention {
                            history.setRetention(proposedRetention, for: kind)
                        }
                    }
                    .buttonStyle(WookeyGlossyButtonStyle())
                    .disabled(proposedRetention == nil)
                }
            }
        }
        .onChange(of: saved, initial: true) { _, value in
            draft = value
            amount = String(value.amount)
        }
    }

    private var proposedRetention: HistoryRetention? {
        guard draft.period == .custom else { return draft }
        guard let amount = Int(amount.trimmingCharacters(in: .whitespaces)), amount > 0 else { return nil }
        var proposed = draft
        proposed.amount = amount
        return proposed
    }

    private func hasChanges(from saved: HistoryRetention) -> Bool {
        draft.period == .custom ? proposedRetention != saved : draft.period != saved.period
    }
}
