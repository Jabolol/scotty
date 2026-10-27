import Foundation
import WebKit

enum Trust {
  static let campus = ["cmu.edu"]
  static let signIn = ["cmu.edu", "duosecurity.com"]

  static func allows(_ url: URL, within domains: [String]) -> Bool {
    guard url.scheme == "https", url.user == nil, url.password == nil,
      let host = url.host()?.lowercased()
    else { return false }
    return domains.contains { host == $0 || host.hasSuffix("." + $0) }
  }

  @MainActor
  static func blocker() async throws -> WKContentRuleList {
    let allowed = signIn.map { domain in
      #"{"trigger":{"url-filter":"^https://([^/@]+\\.)?\#(domain.replacing(".", with: #"\\."#))(:[0-9]+)?/"},"action":{"type":"ignore-previous-rules"}}"#
    }
    let rules =
      [#"{"trigger":{"url-filter":".*"},"action":{"type":"block"}}"#]
      + allowed
      + ["about", "data", "blob"].map {
        #"{"trigger":{"url-filter":"^\#($0):"},"action":{"type":"ignore-previous-rules"}}"#
      }
    guard
      let list = try await WKContentRuleListStore.default()
        .compileContentRuleList(
          forIdentifier: "campus-sign-in",
          encodedContentRuleList: "[\(rules.joined(separator: ","))]")
    else { throw ScottyError.failed("couldn't compile the sign-in content rules") }
    return list
  }
}
