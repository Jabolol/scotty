import Charts
import SwiftUI

extension Color {
  static let download = Color.accentColor
  static let upload = Color.primary
}

struct TrafficGraph: View {
  @Environment(Traffic.self) private var traffic

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 14) {
        TrafficTotal(
          color: .download,
          symbol: "arrow.down",
          total: traffic.samples.last?.received ?? 0,
          rate: traffic.average.download
        )
        TrafficTotal(
          color: .upload,
          symbol: "arrow.up",
          total: traffic.samples.last?.sent ?? 0,
          rate: traffic.average.upload
        )
      }
      .font(.system(size: 12))
      ThroughputChart(samples: traffic.samples, ceiling: traffic.ceiling).frame(height: 48)
    }
    .padding(.horizontal, MenuMetrics.inset)
    .padding(.top, 2)
    .padding(.bottom, 6)
  }
}

private struct TrafficTotal: View {
  let color: Color
  let symbol: String
  let total: UInt64
  let rate: Double

  var body: some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 7, height: 7)
      Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
      Text(Int64(clamping: total), format: .byteCount(style: .file))
        .monospacedDigit()
        .contentTransition(.numericText(value: Double(total)))
      Text("\(Int64(rate), format: .byteCount(style: .file))/s")
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(.tertiary)
    }
    .animation(.smooth(duration: 0.25), value: total)
  }
}

private struct ThroughputChart: View {
  let samples: [Sample]
  let ceiling: Double

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: samples.isEmpty)) { context in
      chart(endingAt: context.date)
    }
  }

  private func chart(endingAt now: Date) -> some View {
    Chart {
      ForEach(samples) { sample in
        line(sample, "Download", sample.download)
        line(sample, "Upload", sample.upload)
      }
    }
    .chartForegroundStyleScale(["Download": Color.download, "Upload": Color.upload])
    .chartYScale(domain: 0...ceiling)
    .chartXScale(domain: now.addingTimeInterval(-Traffic.span)...now)
    .chartLegend(.hidden)
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartPlotStyle { plot in plot.clipped() }
  }

  private func line(_ sample: Sample, _ series: String, _ value: Double) -> some ChartContent {
    LineMark(
      x: .value("Time", sample.time),
      y: .value("Rate", value),
      series: .value("Direction", series)
    )
    .foregroundStyle(by: .value("Direction", series))
    .interpolationMethod(.catmullRom)
    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
  }
}
