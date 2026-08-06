#if DEBUG
import SwiftUI

/// Developer-only diagnostics: the latest redacted dictation records plus
/// session aggregates. Compiled into DEBUG builds only (operating prompt:
/// "developer-only Diagnostics view, disabled in release builds").
/// Shows timings, sizes, and categories — never transcript content.
struct DiagnosticsView: View {
    var metrics: DictationMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                summaryItem("Attempts", "\(metrics.totalAttempts)")
                summaryItem("Completed", "\(metrics.totalCompleted)")
                summaryItem("Median release→paste", msText(metrics.medianReleaseToPasteMs))
                summaryItem("p95 release→paste", msText(metrics.p95ReleaseToPasteMs))
            }
            .padding(.bottom, 4)

            if metrics.records.isEmpty {
                Text("No dictations this session yet.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Table(metrics.records) {
                    TableColumn("Time") { record in
                        Text(record.startedAt, format: .dateTime.hour().minute().second())
                    }
                    .width(70)
                    TableColumn("Result") { record in
                        Text(record.result.rawValue)
                            .foregroundStyle(record.result == .completed ? .primary : .secondary)
                    }
                    TableColumn("Engine") { record in
                        Text(record.engineID?.rawValue ?? "—")
                    }
                    .width(80)
                    TableColumn("Audio (s)") { record in
                        Text(String(format: "%.2f", record.audioDurationSeconds))
                    }
                    .width(60)
                    TableColumn("→Transcript") { record in
                        Text(msText(record.releaseToTranscriptMs))
                    }
                    .width(80)
                    TableColumn("→Paste") { record in
                        Text(msText(record.releaseToPasteMs))
                    }
                    .width(70)
                    TableColumn("Chars") { record in
                        Text(record.transcriptCharacters.map(String.init) ?? "—")
                    }
                    .width(50)
                }
            }

            Text("In-memory only; cleared on quit. No transcript or audio content is recorded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 640, minHeight: 360)
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3).monospacedDigit()
        }
    }

    private func msText(_ value: Int?) -> String {
        value.map { "\($0) ms" } ?? "—"
    }
}
#endif
