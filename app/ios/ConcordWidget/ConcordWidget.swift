import WidgetKit
import SwiftUI

/// Widget bundle entry point — iOS 14+.
@main
struct ConcordWidgetBundle: WidgetBundle {
  var body: some Widget {
    ConcordWidget()
  }
}

/// Main widget configuration.
struct ConcordWidget: Widget {
  let kind: String = "ConcordWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: kind,
      provider: ConcordTimelineProvider()
    ) { entry in
      ConcordWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Concord")
    .description("Today\u2019s symptom status at a glance.")
    .supportedFamilies([
      .systemSmall,
      .systemMedium,
    ])
  }
}
