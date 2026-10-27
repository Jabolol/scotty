import Foundation

struct Challenge: Sendable {
  let opaque: String
  let login: URL
  let final: String
  let cookie: String
}

struct Grant: Sendable {
  let token: String
  let certificate: String
}

struct Gateway: Sendable {
  let session = URLSession(configuration: .ephemeral)
  let version: String

  static func open() async throws -> Gateway {
    let banner = try await Shell.run(Configuration.openconnect, ["--version"])
    let version = banner.split(separator: "\n").first?.split(separator: " ").dropFirst(2).first
    guard let version else {
      throw ScottyError.failed("unexpected openconnect --version output: \(banner)")
    }
    return Gateway(version: String(version))
  }

  func challenge() async throws -> Challenge {
    let document = try await post(
      """
      <config-auth client="vpn" type="init" aggregate-auth-version="2"><version who="vpn">\(version)</version>\
      <device-id>mac-intel</device-id><group-select>\(Configuration.group)</group-select>\
      <group-access>https://\(Configuration.host)/</group-access>\
      <capabilities><auth-method>single-sign-on-v2</auth-method></capabilities></config-auth>
      """)
    guard
      let opaque = document.first("//opaque")?.xmlString,
      let login = document.first("//sso-v2-login")?.stringValue.flatMap(URL.init(string:)),
      let final = document.first("//sso-v2-login-final")?.stringValue,
      let cookie = document.first("//sso-v2-token-cookie-name")?.stringValue
    else {
      throw ScottyError.failed(
        "\(Configuration.host) offered no SSO login for \(Configuration.group)")
    }
    guard Trust.allows(login, within: Trust.campus), let ending = URL(string: final),
      Trust.allows(ending, within: Trust.campus)
    else {
      throw ScottyError.failed(
        "\(Configuration.host) sent a sign-in outside cmu.edu: \(login.host() ?? login.absoluteString)"
      )
    }
    return Challenge(opaque: opaque, login: login, final: final, cookie: cookie)
  }

  func grant(_ challenge: Challenge, token: String) async throws -> Grant {
    let document = try await post(
      """
      <config-auth client="vpn" type="auth-reply" aggregate-auth-version="2"><version who="vpn">\(version)</version>\
      <device-id>mac-intel</device-id><session-token/><session-id/>\(challenge.opaque)\
      <auth><sso-token>\(token.escapedXML)</sso-token></auth></config-auth>
      """)
    guard
      let token = document.first("//session-token")?.stringValue, !token.isEmpty,
      let certificate = document.first("//server-cert-hash")?.stringValue
    else {
      throw ScottyError.failed(
        "\(Configuration.host) rejected the sign-in: \(document.first("//auth/error")?.stringValue ?? "no reason given")"
      )
    }
    return Grant(token: token, certificate: certificate)
  }

  private func post(_ body: String) async throws -> XMLDocument {
    var request = URLRequest(url: URL(string: "https://\(Configuration.host)/")!)
    request.httpMethod = "POST"
    request.httpBody = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + body).utf8)
    request.setValue(
      "AnyConnect-compatible OpenConnect VPN Agent \(version)", forHTTPHeaderField: "User-Agent")
    request.setValue("1", forHTTPHeaderField: "X-Transcend-Version")
    request.setValue("1", forHTTPHeaderField: "X-Aggregate-Auth")
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      throw ScottyError.failed("\(Configuration.host) answered HTTP \(status)")
    }
    return try XMLDocument(data: data)
  }
}

extension XMLDocument {
  fileprivate func first(_ xpath: String) -> XMLNode? { (try? nodes(forXPath: xpath))?.first }
}

extension String {
  fileprivate var escapedXML: String {
    replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
  }
}
