import WidgetKit

/// Timeline entry — carries the data the widget renders.
struct ConcordEntry: TimelineEntry {
  let date: Date
  let status: String
  let gradeText: String
  let grade: Int
  let pendingCount: Int
}

/// Timeline provider — reads data stored by HomeWidget.saveWidgetData
/// from the shared App Group UserDefaults.
struct ConcordTimelineProvider: TimelineProvider {

  private var prefs: UserDefaults? {
    UserDefaults(suiteName: "group.com.concord.app")
  }

  func placeholder(in context: Context) -> ConcordEntry {
    ConcordEntry(
      date: Date(),
      status: "Log today\u2019s symptoms",
      gradeText: "",
      grade: -1,
      pendingCount: 0
    )
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (ConcordEntry) -> Void
  ) {
    completion(loadEntry())
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<ConcordEntry>) -> Void
  ) {
    let entry = loadEntry()
    let timeline = Timeline(entries: [entry], policy: .atEnd)
    completion(timeline)
  }

  private func loadEntry() -> ConcordEntry {
    let status =
      prefs?.string(forKey: "symptom_status")
      ?? "Log today\u2019s symptoms"
    let gradeText = prefs?.string(forKey: "symptom_grade_text") ?? ""
    let grade = prefs?.integer(forKey: "symptom_grade") ?? -1
    let pendingCount = prefs?.integer(forKey: "pending_sync_count") ?? 0
    return ConcordEntry(
      date: Date(),
      status: status,
      gradeText: gradeText,
      grade: grade,
      pendingCount: pendingCount
    )
  }
}
