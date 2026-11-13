import AppKit
import SwiftUI

extension SettingsView {
    // MARK: - Focus Mode Settings

    func saveFocusMapping() {
        let trimmed = focusDraftIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, focusDraftSceneId != nil else { return }
        switch focusEditor {
        case .none:
            return
        case .create:
            appState.addFocusMapping(FocusMapping(focusIdentifier: trimmed, focusDisplayName: trimmed, sceneId: focusDraftSceneId))
        case .edit(let id):
            if var updated = appState.focusMappings.first(where: { $0.id == id }) {
                updated.focusIdentifier = trimmed
                updated.focusDisplayName = trimmed
                updated.sceneId = focusDraftSceneId
                appState.updateFocusMapping(updated)
            }
        }
        focusEditor = .none
        focusDraftIdentifier = ""
        focusDraftSceneId = nil
    }

    var focusSettings: some View {
        VStack(spacing: 12) {
            settingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.focusTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ink)
                        Spacer()
                        Button {
                            focusEditor = .create
                            focusDraftIdentifier = ""
                            focusDraftSceneId = nil
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(width: 26, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .lcIconLabel("a11y.focus.add")
                    }

                    if appState.focusMappings.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "target")
                                .foregroundStyle(muted)
                                .frame(width: 24, height: 24)
                            Text(L10n.focusEmptyMessage)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(muted)
                            Spacer()
                        }
                        .padding(12)
                        .liquidGlassSurface(radius: 14)
                    } else {
                        ForEach(appState.focusMappings) { mapping in
                            HStack(spacing: 8) {
                                Image(systemName: "target")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 20, height: 20)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(mapping.focusDisplayName)
                                        .font(.system(size: 11, weight: .semibold))
                                    let sceneName = appState.userScenes.first(where: { $0.id == mapping.sceneId })?.title ?? "—"
                                    Text(sceneName)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(muted)
                                }
                                
                                Spacer()
                                
                                Toggle("a11y.focus.mapping.enabled", isOn: Binding(
                                    get: { mapping.isEnabled },
                                    set: { enabled in
                                        var updated = mapping
                                        updated.isEnabled = enabled
                                        appState.updateFocusMapping(updated)
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(accent)
                                .help("a11y.focus.mapping.enabled")
                                
                                Button {
                                    focusEditor = .edit(mapping.id)
                                    focusDraftIdentifier = mapping.focusIdentifier
                                    focusDraftSceneId = mapping.sceneId
                                } label: {
                                    Image(systemName: "pencil.circle")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(accent)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("help.focus.edit")

                                Button {
                                    appState.removeFocusMapping(mapping.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.red)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("help.focus.delete")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .liquidGlassSurface(radius: 10)
                        }
                    }

                    if focusEditor.isOpen {
                        InlineEditorForm(onSave: saveFocusMapping, onCancel: { focusEditor = .none }) {
                            TextField(L10n.focusIdentifierPlaceholder, text: $focusDraftIdentifier)
                                .font(.system(size: 11, weight: .medium))
                                .textFieldStyle(.roundedBorder)

                            Picker(L10n.focusScenePlaceholder, selection: $focusDraftSceneId) {
                                Text("—").tag(UUID?.none)
                                ForEach(appState.userScenes) { scene in
                                    Text(scene.title).tag(UUID?.some(scene.id))
                                }
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                    }
                }
            }

            focusAutomationGroup
        }
        // A mapping deleted (or switched off by a scene deletion) while its form is open.
        .onReceive(appState.$focusMappings) { mappings in
            focusEditor = focusEditor.resolved(existingIDs: mappings.map(\.id))
        }
    }

    /// Setup hint + the exact `lampcontrol://focus?mode=…` URLs to paste in a Shortcuts automation.
    var focusAutomationGroup: some View {
        // Only modes that actually have a mapping get a URL — a URL for an
        // unmapped mode would silently do nothing.
        let builtInNames = Dictionary(
            appState.availableFocusModes.map { ($0.identifier.lowercased(), $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        let mappedRows: [(title: String, mode: String)] = appState.focusMappings
            .map(\.focusIdentifier)
            .filter { seen.insert($0.lowercased()).inserted }
            .map { (builtInNames[$0.lowercased()] ?? $0, $0) }
        let rows = mappedRows
            + [(NSLocalizedString("focus.automation.off", comment: ""), FocusAutomationURL.offMode)]

        return settingsGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("focus.automation.title")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)

                hint("focus.automation.hint")

                ForEach(rows, id: \.mode) { row in
                    focusURLRow(title: row.title, mode: row.mode)
                }
            }
        }
    }

    func focusURLRow(title: String, mode: String) -> some View {
        let url = FocusAutomationURL.urlString(forMode: mode)
        let didCopy = copiedFocusMode == mode

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(url)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(muted)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                copiedFocusMode = mode
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    if copiedFocusMode == mode { copiedFocusMode = nil }
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("focus.automation.copy.help")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .liquidGlassSurface(radius: 10)
    }
}
