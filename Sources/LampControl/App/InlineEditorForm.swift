import SwiftUI

/// The create / edit form shared by the Rooms and Focus sections of Settings: the section's
/// fields followed by Save and Cancel. Which form is open is tracked by one `SectionEditor`
/// per section, so there is never a second form (and a second way to save the same thing).
struct InlineEditorForm<Fields: View>: View {
    let onSave: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let fields: () -> Fields

    var body: some View {
        VStack(spacing: 8) {
            fields()

            HStack(spacing: 8) {
                Button(L10n.save, action: onSave)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .liquidGlassButtonStyle(prominent: true)

                Button(L10n.cancel, action: onCancel)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .liquidGlassButtonStyle()
            }
        }
        .padding(10)
        .liquidGlassSurface(radius: 14)
    }
}
