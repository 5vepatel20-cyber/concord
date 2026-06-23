import SwiftUI
import WidgetKit

/// SwiftUI view rendered inside the widget.
struct ConcordWidgetEntryView: View {
  var entry: ConcordEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      // Header
      HStack {
        Text("Concord")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.secondary)

        if entry.pendingCount > 0 {
          Spacer()
          Text("\(entry.pendingCount) pending")
            .font(.system(size: 11))
            .foregroundColor(.purple)
        }
      }

      Spacer()

      // Status
      Text(entry.status)
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(.primary)

      // Grade detail
      if !entry.gradeText.isEmpty && entry.grade >= 0 {
        Text(entry.gradeText)
          .font(.system(size: 12))
          .foregroundColor(gradeColor)
      }
    }
    .padding(14)
    .containerBackground(.background, for: .widget)
  }

  private var gradeColor: Color {
    switch entry.grade {
    case 1: return .green
    case 2: return .orange
    case 3: return .red
    default: return .secondary
    }
  }
}
