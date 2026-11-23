import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WookeyCore

struct NewLayoutEditor: View {
    @State private var draft = WindowLayout()
    var onCancel: () -> Void
    var onSave: (WindowLayout) -> Void

    var body: some View {
        LayoutEditorView(layout: $draft, onBack: onCancel, onSave: onSave)
    }
}

struct LayoutEditorView: View {
    @Environment(\.wookeyTheme) private var theme
    @Environment(WookeyRuntime.self) private var runtime
    @Binding var layout: WindowLayout
    var onBack: () -> Void
    var onDelete: (() -> Void)? = nil
    var onSave: ((WindowLayout) -> Void)? = nil

    @State private var selectedPlacementID: UUID?
    @State private var automaticPlacementIDs = Set<UUID>()
    @State private var displays: [DisplayInfo] = []
    @State private var showsAppPicker = false
    @State private var openedInitialPicker = false
    @State private var showsShortcut = false
    @State private var showsMoreZones = false
    @State private var showsDeleteConfirmation = false

    private var selectedPlacement: AppWindowPlacement? {
        layout.placements.first { $0.id == selectedPlacementID } ?? layout.placements.first
    }

    private var previewDisplay: DisplayInfo? {
        if let selectedPlacement {
            let id = displayID(for: selectedPlacement)
            return displays.first { $0.id == id }
        }
        return displays.first
    }

    private var visiblePlacements: [AppWindowPlacement] {
        guard let previewDisplay else { return [] }
        return layout.placements.filter { displayID(for: $0) == previewDisplay.id }
    }

    private var layoutName: String { layout.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            WookeyEditorHeader(
                title: $layout.name,
                subtitle: layout.placements.isEmpty
                    ? "함께 사용할 앱을 고르고 화면에 배치하세요."
                    : "\(layout.placements.count)개 앱의 창을 한 번에 배치합니다.",
                onBack: onBack
            ) {
                if onDelete != nil {
                    WookeyDeleteButton(title: "레이아웃 삭제") { showsDeleteConfirmation = true }
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 22) {
                            applicationsSection.frame(width: 232)
                            placementSection.frame(minWidth: 362)
                        }
                        VStack(alignment: .leading, spacing: 22) {
                            applicationsSection
                            placementSection
                        }
                    }

                    if !layout.placements.isEmpty || !layout.shortcut.steps.isEmpty {
                        shortcutSection
                    }

                    if let summary = runtime.lastRun, summary.workflowID == layout.id {
                        PlainPanel { RunSummaryView(summary: summary) }
                    }
                }
                .padding(WookeyPageMetrics.padding)
                .frame(maxWidth: WookeyPageMetrics.maximumWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()
            footer
        }
        .navigationTitle(layout.name)
        .onAppear {
            refreshDisplays()
            if onSave != nil, !openedInitialPicker, !displays.isEmpty {
                openedInitialPicker = true
                showsAppPicker = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshDisplays()
        }
        .sheet(isPresented: $showsAppPicker) {
            LayoutApplicationPicker(
                existingIDs: Set(layout.placements.map(\.bundleIdentifier)),
                onAdd: addApplications
            )
            .presentationBackground(theme.canvas)
        }
        .alert("레이아웃을 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) { onDelete?() }
        } message: {
            Text("‘\(layout.name)’과 이 레이아웃을 사용하는 워크플로 동작이 함께 삭제됩니다. 이 작업은 되돌릴 수 없습니다.")
        }
    }

    private var applicationsSection: some View {
        WookeySection(title: "배치할 앱") {
            if layout.placements.isEmpty {
                PlainPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        WookeyActionIcon(symbol: "app", tint: .teal, size: 30)
                        Text("앱을 골라 시작하세요").font(.headline)
                        Text("여러 앱을 한 번에 추가할 수 있어요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        addApplicationButton
                    }
                }
            } else {
                VStack(spacing: 4) {
                    ForEach(layout.placements) { placement in
                        placementRow(placement)
                    }
                }
                addApplicationButton
            }
        }
    }

    private var addApplicationButton: some View {
        Button("앱 추가", wookeyIcon: "plus") { showsAppPicker = true }
            .buttonStyle(WookeyGlossyButtonStyle())
            .disabled(displays.isEmpty)
    }

    private func placementRow(_ placement: AppWindowPlacement) -> some View {
        let isSelected = selectedPlacement?.id == placement.id
        let display = displays.first { $0.id == displayID(for: placement) }
        return HStack(spacing: 6) {
            Button {
                selectedPlacementID = placement.id
            } label: {
                HStack(spacing: 9) {
                    LayoutApplicationIcon(
                        url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: placement.bundleIdentifier),
                        size: 25
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(placement.appName).font(.subheadline.weight(.semibold))
                        Text(display == nil ? "모니터 연결 안 됨" : placement.zone.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(WookeyHoverButtonStyle(selected: isSelected))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            WookeyDeleteButton(title: "\(placement.appName) 배치에서 제거") {
                layout.placements.removeAll { $0.id == placement.id }
                automaticPlacementIDs.remove(placement.id)
            }
        }
    }

    private var placementSection: some View {
        WookeySection(title: "화면 배치") {
            PlainPanel {
                VStack(alignment: .leading, spacing: 12) {
                    if let placement = selectedPlacement {
                        HStack(spacing: 8) {
                            Text(placement.appName).font(.headline).lineLimit(1)
                            Spacer(minLength: 0)
                            monitorControl(for: placement)
                        }
                    } else if let previewDisplay {
                        Text(previewDisplay.target.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if let previewDisplay {
                        DisplayPreview(
                            display: previewDisplay,
                            placements: visiblePlacements,
                            selectedID: selectedPlacement?.id,
                            select: { selectedPlacementID = $0 }
                        )
                    } else {
                        Label(
                            displays.isEmpty ? "연결된 모니터가 없습니다" : "위에서 연결된 모니터를 선택하세요",
                            systemImage: "display"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                    }

                    if let placement = selectedPlacement, previewDisplay != nil {
                        Divider()
                        HStack {
                            Text("배치 위치").font(.subheadline.weight(.semibold))
                            Spacer()
                            if let zones = Self.arrangedZones(for: visiblePlacements.count),
                               visiblePlacements.map(\.zone) != zones {
                                Button("자동 배치") { arrangeVisibleApps(in: zones) }
                                    .controlSize(.small)
                                    .help("이 모니터의 앱 창을 겹치지 않게 배치합니다.")
                            }
                        }
                        zoneGrid([.full, .leftHalf, .rightHalf], placement: placement)
                        if visiblePlacements.contains(where: {
                            $0.id != placement.id && !$0.zone.normalizedRect.intersection(placement.zone.normalizedRect).isEmpty
                        }) {
                            Label("선택한 영역이 다른 앱과 겹칩니다.", systemImage: "square.on.square")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        DisclosureGroup("더 많은 배치", isExpanded: $showsMoreZones) {
                            VStack(spacing: 8) {
                                zoneGrid([.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds], placement: placement)
                                zoneGrid([.topLeft, .topRight, .bottomLeft, .bottomRight], placement: placement)
                            }
                            .padding(.top, 8)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func monitorControl(for placement: AppWindowPlacement) -> some View {
        if displays.count > 1 || previewDisplay == nil {
            Picker("모니터", selection: Binding(
                get: { displayID(for: placement) },
                set: { id in
                    guard let display = displays.first(where: { $0.id == id }),
                          let index = index(of: placement) else { return }
                    layout.placements[index].display = display.target
                    automaticPlacementIDs.remove(placement.id)
                }
            )) {
                if previewDisplay == nil {
                    Text("\(placement.display.name) · 연결 안 됨").tag(displayID(for: placement))
                }
                ForEach(displays) { display in
                    Text(display.target.name).tag(display.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 185)
            .disabled(displays.isEmpty)
        } else if let previewDisplay {
            Text(previewDisplay.target.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func zoneGrid(_ zones: [LayoutZone], placement: AppWindowPlacement) -> some View {
        let selectedZone = placement.zone.normalizedRect
        let columns = zones.count == 3
            ? Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
            : [GridItem(.adaptive(minimum: 92), spacing: 6)]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(zones) { zone in
                let isSelected = selectedZone == zone.normalizedRect
                Button {
                    guard let index = index(of: placement) else { return }
                    layout.placements[index].zone = zone
                    automaticPlacementIDs.remove(placement.id)
                } label: {
                    VStack(spacing: 4) {
                        LayoutZoneGlyph(zone: zone)
                            .frame(width: 29, height: 20)
                        Text(zone.title)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(WookeyHoverButtonStyle(selected: isSelected))
                .background(theme.canvas, in: .rect(cornerRadius: 7))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var shortcutSection: some View {
        PlainPanel {
            let label = layout.shortcut.steps.isEmpty ? "단축키 추가 (선택)" : "단축키 · \(layout.shortcut.displayName)"
            DisclosureGroup(label, isExpanded: $showsShortcut) {
                ShortcutRecorderView(shortcut: $layout.shortcut)
                    .padding(.top, 10)
            }
            .font(.subheadline.weight(.semibold))
            if let error = runtime.hotkeys.layoutRegistrationErrors[layout.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let onSave {
                Spacer()
                Button("취소", action: onBack)
                    .keyboardShortcut(.cancelAction)
                Button {
                    var saved = layout
                    saved.name = layoutName
                    onSave(saved)
                } label: {
                    WookeyControlLabel(title: "레이아웃 저장", symbol: "checkmark.circle.fill")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .buttonStyle(WookeyHoverButtonStyle(selected: true))
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(layout.placements.isEmpty || layoutName.isEmpty)
            } else {
                WookeySaveStatus()
                Spacer(minLength: 0)
                if !layout.placements.isEmpty, !runtime.permissions.accessibilityGranted {
                    Text("적용하려면 손쉬운 사용 권한이 필요합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("권한 설정", action: runtime.permissions.requestAccessibility)
                } else {
                    Button("레이아웃 적용", wookeyIcon: "play.fill") { runtime.run(layoutID: layout.id) }
                        .buttonStyle(WookeyGlossyButtonStyle())
                        .controlSize(.large)
                        .disabled(layout.placements.isEmpty || displays.isEmpty
                                  || runtime.runner.runningWorkflowID == layout.id
                                  || runtime.runner.queuedWorkflowIDs.contains(layout.id))
                        .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
        .padding(.horizontal, WookeyPageMetrics.padding)
        .padding(.vertical, 12)
        .background(theme.panel)
    }

    private func index(of placement: AppWindowPlacement) -> Int? {
        layout.placements.firstIndex { $0.id == placement.id }
    }

    private func displayID(for placement: AppWindowPlacement) -> String {
        runtime.layoutController.displayMappings[placement.display.uuid] ?? placement.display.uuid
    }

    private func refreshDisplays() {
        displays = runtime.layoutController.availableDisplays
    }

    private func addApplications(_ applications: [InstalledApplication]) {
        let existingIDs = Set(layout.placements.map(\.bundleIdentifier))
        let additions = applications.filter { !existingIDs.contains($0.id) }
        guard let display = previewDisplay ?? displays.first, !additions.isEmpty else { return }
        let occupied = layout.placements.filter { displayID(for: $0) == display.id }
        let arrangement = occupied.allSatisfy { automaticPlacementIDs.contains($0.id) }
            ? Self.arrangedZones(for: occupied.count + additions.count)
            : nil
        let suggestions: [LayoutZone] = [
            .full, .leftHalf, .rightHalf, .leftThird, .centerThird, .rightThird,
            .topLeft, .topRight, .bottomLeft, .bottomRight
        ]
        var occupiedRects = occupied.map(\.zone.normalizedRect)
        let placements = additions.enumerated().map { offset, application in
            let zone = arrangement?[occupied.count + offset] ?? suggestions.first { candidate in
                occupiedRects.allSatisfy { $0.intersection(candidate.normalizedRect).isEmpty }
            } ?? .rightHalf
            occupiedRects.append(zone.normalizedRect)
            return AppWindowPlacement(
                bundleIdentifier: application.id, appName: application.displayName, display: display.target, zone: zone
            )
        }
        layout.placements = placementsArranged(occupied, in: arrangement) + placements
        automaticPlacementIDs.formUnion(placements.map(\.id))
        selectedPlacementID = placements.first?.id
    }

    private func arrangeVisibleApps(in zones: [LayoutZone]) {
        let visible = visiblePlacements
        layout.placements = placementsArranged(visible, in: zones)
        automaticPlacementIDs.subtract(visible.map(\.id))
    }

    private func placementsArranged(_ placements: [AppWindowPlacement], in zones: [LayoutZone]?) -> [AppWindowPlacement] {
        guard let zones else { return layout.placements }
        let zonesByID = Dictionary(uniqueKeysWithValues: zip(placements.map(\.id), zones))
        return layout.placements.map { placement in
            guard let zone = zonesByID[placement.id] else { return placement }
            var arranged = placement
            arranged.zone = zone
            return arranged
        }
    }

    private static func arrangedZones(for count: Int) -> [LayoutZone]? {
        switch count {
        case 2: [.leftHalf, .rightHalf]
        case 3: [.leftThird, .centerThird, .rightThird]
        case 4: [.topLeft, .topRight, .bottomLeft, .bottomRight]
        default: nil
        }
    }
}

private struct LayoutZoneGlyph: View {
    var zone: LayoutZone

    var body: some View {
        GeometryReader { geometry in
            let rect = zone.normalizedRect
            RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.6))
            RoundedRectangle(cornerRadius: 2)
                .fill(.secondary.opacity(0.55))
                .frame(width: max(0, geometry.size.width * rect.width - 4),
                       height: max(0, geometry.size.height * rect.height - 4))
                .position(
                    x: geometry.size.width * rect.midX,
                    y: geometry.size.height * (1 - rect.midY)
                )
        }
        .accessibilityHidden(true)
    }
}

private struct DisplayPreview: View {
    @Environment(\.wookeyTheme) private var theme
    let display: DisplayInfo
    let placements: [AppWindowPlacement]
    let selectedID: UUID?
    let select: (UUID) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(theme.canvas)
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(.separator.opacity(0.65))

                if placements.isEmpty {
                    Text("앱을 추가하면 배치가 여기에 표시됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(placements) { placement in
                    let rect = placement.zone.normalizedRect
                    let isSelected = placement.id == selectedID
                    Button {
                        select(placement.id)
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? theme.selectionTint.opacity(0.62) : theme.panel)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(theme.accent.opacity(isSelected ? 0.65 : 0.25))
                            }
                            .overlay {
                                Text(placement.appName)
                                    .font(.caption.weight(isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? theme.selectionInk : .primary)
                                    .lineLimit(1)
                                    .padding(5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(placement.appName), \(placement.zone.title)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .frame(width: max(0, geometry.size.width * rect.width - 6),
                           height: max(0, geometry.size.height * rect.height - 6))
                    .position(
                        x: geometry.size.width * rect.midX,
                        y: geometry.size.height * (1 - rect.midY)
                    )
                    .zIndex(isSelected ? 1 : 0)
                }
            }
        }
        .aspectRatio(max(0.6, display.visibleFrame.width / max(1, display.visibleFrame.height)), contentMode: .fit)
        .frame(maxHeight: 200)
        .frame(maxWidth: .infinity)
    }
}

private struct LayoutApplicationIcon: View {
    var url: URL?
    var size: CGFloat

    var body: some View {
        Group {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
            } else {
                WookeyActionIcon(symbol: "app", tint: .teal, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct LayoutApplicationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wookeyTheme) private var theme
    @State private var applications: [InstalledApplication] = []
    @State private var selection: [InstalledApplication] = []
    @State private var runningIDs = Set<String>()
    @State private var query = ""
    @State private var isLoading = true
    @State private var showsFilePicker = false
    @State private var importError: String?
    @FocusState private var searchFocused: Bool

    let existingIDs: Set<String>
    let onAdd: ([InstalledApplication]) -> Void

    private var matches: [InstalledApplication] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return applications.filter { !existingIDs.contains($0.id) && $0.matchesSearchTerms(terms) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("배치할 앱 선택").font(.title2.weight(.semibold))

            WookeySearchField(prompt: "앱 이름 검색", text: $query)
                .focused($searchFocused)

            appList

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("찾아보기…") { showsFilePicker = true }
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    onAdd(selection)
                    dismiss()
                } label: {
                    WookeyControlLabel(title: selection.isEmpty ? "추가" : "\(selection.count)개 앱 추가", symbol: "plus")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(WookeyHoverButtonStyle(selected: true))
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 510, height: 480)
        .background(theme.canvas)
        .defaultFocus($searchFocused, true)
        .task { await loadApps() }
        .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: [.application], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let matchingApps = urls.compactMap(Self.application(at:))
                for app in matchingApps {
                    if !applications.contains(where: { $0.id == app.id }) { applications.append(app) }
                    if !existingIDs.contains(app.id), !selection.contains(where: { $0.id == app.id }) { selection.append(app) }
                }
                importError = matchingApps.isEmpty ? "선택한 위치에서 앱을 열 수 없습니다." : nil
                if !matchingApps.isEmpty { query = "" }
            case .failure:
                importError = "선택한 앱을 불러오지 못했습니다."
            }
        }
    }

    @ViewBuilder private var appList: some View {
        if isLoading {
            ProgressView("앱 목록을 불러오는 중…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if matches.isEmpty {
            Group {
                if query.isEmpty {
                    ContentUnavailableView("추가할 앱이 없습니다", systemImage: "macwindow")
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                let running = matches.filter { runningIDs.contains($0.id) }
                if !running.isEmpty {
                    Section("실행 중") { ForEach(running, content: appRow) }
                }
                let other = matches.filter { !runningIDs.contains($0.id) }
                if !other.isEmpty {
                    Section("설치된 앱") { ForEach(other, content: appRow) }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(theme.panel, in: .rect(cornerRadius: 9))
        }
    }

    private func appRow(_ application: InstalledApplication) -> some View {
        Toggle(isOn: Binding(
            get: { selection.contains { $0.id == application.id } },
            set: { checked in
                selection.removeAll { $0.id == application.id }
                if checked { selection.append(application) }
            }
        )) {
            HStack(spacing: 8) {
                LayoutApplicationIcon(url: URL(fileURLWithPath: application.path), size: 22)
                Text(application.displayName).lineLimit(1)
            }
        }
        .toggleStyle(.checkbox)
    }

    private func loadApps() async {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .compactMap { $0.bundleURL.flatMap(Self.application(at:)) }
        runningIDs = Set(running.map(\.id))
        let installed = await InstalledApplicationCatalog.load()
        guard !Task.isCancelled else { return }
        let known = Dictionary((applications + running + installed).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        applications = known.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        isLoading = false
    }

    private static func application(at url: URL) -> InstalledApplication? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApplication(bundleIdentifier: id, displayName: name, path: url.path)
    }
}
