import SwiftUI

// Kept outside the plot: the exact amount never covers bars, axes or labels.
// Each chart owns one optional selection, so a second tap replaces the first.
struct IncomeBarReadout: View {
    let label: String
    let cents: Int
    let identifier: String
    var clear: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Text("\(label) · \(Money.display(cents))")
                .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
            Spacer(minLength: 0)
            Button(action: clear) { Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44) }
                .buttonStyle(.plain).accessibilityLabel("Chiudi valore selezionato")
        }.foregroundStyle(PivotTheme.accent)
    }
}
