import AppKit
import SwiftUI

extension SettingsView {
    func saveRoom() {
        let trimmed = roomDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch roomEditor {
        case .none: return
        case .create: appState.addRoom(name: trimmed)
        case .edit(let id): appState.renameRoom(id, to: trimmed)
        }
        roomEditor = .none
        roomDraftName = ""
    }

    var devicesSettings: some View {
        VStack(spacing: 12) {
            settingsGroup {
                infoRow("devices.detected", value: "\(appState.lamps.count)", icon: "lightbulb.2")
                infoRow("devices.online",   value: "\(appState.lamps.filter(\.online).count)", icon: "wifi")
                infoRow("devices.sync",     value: syncSummary, icon: "arrow.triangle.2.circlepath")
            }

            settingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("devices.display.options")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ink)
                    
                    Toggle("devices.hide.offline", isOn: $appState.hideOfflineLamps)
                        .font(.system(size: 12, weight: .semibold))
                        .toggleStyle(.switch)
                        .tint(accent)
                }
            }

            Button {
                Task { await appState.syncLamps() }
            } label: {
                Label("devices.sync.now", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .liquidGlassButtonStyle(prominent: true)
            .tint(accent)
            .disabled(appState.isBusy || !appState.canSync)
            .opacity(appState.isBusy || !appState.canSync ? 0.55 : 1)

            hint(appState.canSync ? "devices.sync.hint" : "devices.sync.required.hint")

            // Room management section
            settingsGroup {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("devices.rooms.title")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ink)
                        Spacer()
                        Button {
                            roomEditor = .create
                            roomDraftName = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(width: 26, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .lcIconLabel("a11y.room.add")
                    }

                    // List rooms with edit/delete
                    ForEach(appState.rooms) { room in
                        HStack(spacing: 8) {
                            Image(systemName: "door.left.hand.open")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(width: 20, height: 20)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(room.name)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(L10n.lampCount(room.lampIds.count))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(muted)
                            }

                            Spacer()

                            Button {
                                roomEditor = .edit(room.id)
                                roomDraftName = room.name
                            } label: {
                                Image(systemName: "pencil.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("help.room.edit")

                            Button {
                                appState.deleteRoom(room.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.red)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("help.room.delete")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .liquidGlassSurface(radius: 10)
                    }

                    // Lamp assignment
                    if !appState.lamps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("room.assign.lamps")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(muted)
                            
                            ForEach(appState.lamps) { lamp in
                                HStack(spacing: 8) {
                                    Text(lamp.name)
                                        .font(.system(size: 11, weight: .medium))
                                    Spacer()
                                    let current = appState.roomForLamp(lamp.id)?.name ?? L10n.roomUnassigned
                                    Text(current)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(muted)

                                    Menu {
                                        Button(L10n.roomUnassigned) { appState.unassignLamp(lamp.id) }
                                        ForEach(appState.rooms) { room in
                                            Button(room.name) { appState.assignLamp(lamp.id, to: room.id) }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(accent)
                                    }
                                    .menuStyle(BorderlessButtonMenuStyle())
                                    .help("help.room.assign")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .liquidGlassSurface(radius: 10)
                            }
                        }
                    }

                    if roomEditor.isOpen {
                        InlineEditorForm(onSave: saveRoom, onCancel: { roomEditor = .none }) {
                            TextField("room.name.placeholder", text: $roomDraftName)
                                .font(.system(size: 11, weight: .medium))
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(saveRoom)
                        }
                    }
                }
            }
        }
        // A room deleted while its form is open.
        .onReceive(appState.$rooms) { rooms in
            roomEditor = roomEditor.resolved(existingIDs: rooms.map(\.id))
        }
    }

    var syncSummary: String {
        guard let lastSyncDate = appState.lastSyncDate else { return L10n.syncNever }
        return lastSyncDate.formatted(date: .omitted, time: .shortened)
    }
}
