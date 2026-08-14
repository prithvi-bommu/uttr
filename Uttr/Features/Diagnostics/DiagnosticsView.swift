import SwiftUI

struct DiagnosticsView: View {
    var metrics: DictationMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryBar
            polishRatesBar
            recordsContent
            footer
        }
        .padding()
        .frame(minWidth: 960, minHeight: 360)
    }

    private var summaryBar: some View {
        HStack(spacing: 24) {
            summaryItem("Attempts", "\(metrics.totalAttempts)")
            summaryItem("Completed", "\(metrics.totalCompleted)")
            summaryItem("Median release→paste", msText(metrics.medianReleaseToPasteMs))
            summaryItem("p95 release→paste", msText(metrics.p95ReleaseToPasteMs))
            summaryItem("p99 release→paste", msText(metrics.p99ReleaseToPasteMs))
        }
    }

    private var polishRatesBar: some View {
        HStack(spacing: 24) {
            summaryItem("Fallback rate", rateText(metrics.fallbackRate))
            summaryItem("Provider failure", rateText(metrics.providerFailureRate))
            summaryItem("Validation rejection", rateText(metrics.validationRejectionRate))
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var recordsContent: some View {
        if metrics.records.isEmpty {
            Text("No dictations this session yet.")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            recordsTable
        }
    }

    private var recordsTable: some View {
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
            TableColumn("Audio") { record in
                Text(String(format: "%.1fs", record.audioDurationSeconds))
            }
            .width(50)
            tableColumnsTimeline
            tableColumnsPolish
        }
    }

    @TableColumnBuilder<DictationRecord, Never>
    private var tableColumnsTimeline: some TableColumnContent<DictationRecord, Never> {
        TableColumn("→Transcript") { record in
            Text(msText(record.releaseToTranscriptMs))
        }
        .width(80)
        TableColumn("→Clean") { record in
            Text(msText(record.transcriptToLocalCleanMs))
        }
        .width(60)
        TableColumn("→AIReq") { record in
            Text(msText(record.localCleanToAiRequestMs))
        }
        .width(60)
        TableColumn("→AIResp") { record in
            Text(msText(record.aiRequestToResponseMs))
        }
        .width(60)
        TableColumn("→Paste") { record in
            Text(msText(record.responseToPasteMs))
        }
        .width(60)
        TableColumn("Total") { record in
            Text(msText(record.releaseToPasteMs))
        }
        .width(60)
    }

    @TableColumnBuilder<DictationRecord, Never>
    private var tableColumnsPolish: some TableColumnContent<DictationRecord, Never> {
        TableColumn("Polish") { record in
            Text(record.polishOutcome?.rawValue ?? "—")
                .foregroundStyle(polishColor(record.polishOutcome))
        }
        .width(100)
        TableColumn("Budget") { record in
            Text(record.configuredBudgetMs.map { "\($0)" } ?? "—")
        }
        .width(50)
        TableColumn("Chars") { record in
            Text(record.transcriptCharacters.map(String.init) ?? "—")
        }
        .width(50)
    }

    private var footer: some View {
        Text("In-memory only; cleared on quit. No transcript or audio content is recorded.")
            .font(.caption)
            .foregroundStyle(.secondary)
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

    private func rateText(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
    }

    private func polishColor(_ outcome: PolishOutcome?) -> Color {
        switch outcome {
        case .aiSuccess: Color.primary
        case .deadlineFallback, .skippedNoTime: Color.orange
        case .providerFailure, .invalidResponse: Color.red
        case .cancelled, .noPolisher, nil: Color.secondary
        }
    }
}
