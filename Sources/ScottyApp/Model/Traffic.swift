import Foundation
import Observation
import ScottyKit

struct Sample: Identifiable, Equatable {
  let time: Date
  let download: Double
  let upload: Double
  let received: UInt64
  let sent: UInt64

  var id: Date { time }
}

struct Speed: Equatable {
  static let zero = Speed(download: 0, upload: 0)

  let download: Double
  let upload: Double
}

@MainActor
@Observable
final class Traffic {
  static let span: TimeInterval = 120
  private static let smoothing = 0.35
  private static let readout: TimeInterval = 1
  private static let floor: Double = 1024
  private static let headroom = 1.15
  private static let settle = 0.08

  private(set) var samples: [Sample] = []
  private(set) var average = Speed.zero
  private(set) var ceiling = Traffic.floor * Traffic.headroom
  private(set) var flows: [Flow] = []
  private(set) var hostnames: [String: String] = [:]
  private var watchers = 0
  private var averaged: Date?
  private var last: (time: Date, counters: Counters)?

  var isWatched: Bool { watchers > 0 }

  func isQuiet(below rate: Double) -> Bool {
    average.download < rate && average.upload < rate
  }

  func watch(_ active: Bool) {
    watchers += active ? 1 : -1
  }

  func reset() {
    samples = []
    average = .zero
    ceiling = Self.floor * Self.headroom
    flows = []
    hostnames = [:]
    averaged = nil
    last = nil
  }

  func record(_ counters: Counters, at time: Date = .now) {
    let previous = last
    last = (time, counters)
    guard let previous, time > previous.time else { return }
    let elapsed = time.timeIntervalSince(previous.time)
    let download = Double(counters.received &- previous.counters.received) / elapsed
    let upload = Double(counters.sent &- previous.counters.sent) / elapsed
    let horizon = time.addingTimeInterval(-Self.span)
    let sample = Sample(
      time: time,
      download: smooth(download, after: samples.last?.download),
      upload: smooth(upload, after: samples.last?.upload),
      received: counters.received,
      sent: counters.sent
    )
    samples = samples.drop { $0.time < horizon } + [sample]
    let peak =
      max(samples.map { max($0.download, $0.upload) }.max() ?? 0, Self.floor) * Self.headroom
    ceiling = peak > ceiling ? peak : ceiling + (peak - ceiling) * Self.settle
    guard averaged.map({ time.timeIntervalSince($0) >= Self.readout }) ?? true else { return }
    averaged = time
    let count = Double(samples.count)
    average = Speed(
      download: samples.reduce(0) { $0 + $1.download } / count,
      upload: samples.reduce(0) { $0 + $1.upload } / count
    )
  }

  func refreshFlows(through address: String) async {
    guard let found = try? await Activity.flows(through: address) else { return }
    flows = found.sorted { $0.received + $0.sent > $1.received + $1.sent }
    for remote in Set(found.map(\.remote)).subtracting(hostnames.keys) {
      hostnames[remote] = await Activity.hostname(remote) ?? remote
    }
  }

  private func smooth(_ rate: Double, after prior: Double?) -> Double {
    prior.map { $0 + (rate - $0) * Self.smoothing } ?? rate
  }
}
