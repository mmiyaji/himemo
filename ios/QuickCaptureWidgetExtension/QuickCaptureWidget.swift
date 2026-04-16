import SwiftUI
import WidgetKit

private struct QuickCaptureEntry: TimelineEntry {
    let date: Date
}

private struct QuickCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickCaptureEntry {
        QuickCaptureEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickCaptureEntry) -> Void) {
        completion(QuickCaptureEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickCaptureEntry>) -> Void) {
        let entry = QuickCaptureEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct QuickCaptureWidget: Widget {
    private let kind = "QuickCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickCaptureProvider()) { entry in
            QuickCaptureWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Memo")
        .description("Open the text-only quick memo capture surface.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct QuickCaptureWidgetView: View {
    let entry: QuickCaptureEntry

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.973, green: 0.984, blue: 0.992))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Color(red: 0.06, green: 0.33, blue: 0.64))
                    Text("Quick Memo")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Text("Send a text-only note to Daily Notes without opening the full app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Link(destination: URL(string: "himemo://widget-capture")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Open capture")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.06, green: 0.33, blue: 0.64))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .widgetURL(URL(string: "himemo://widget-capture"))
    }
}
