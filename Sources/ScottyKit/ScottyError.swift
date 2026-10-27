import Foundation

public enum ScottyError: LocalizedError, Equatable {
  case failed(String)
  case needsAttention
  case busy

  public var errorDescription: String? {
    switch self {
    case .failed(let message): message
    case .needsAttention: "Sign-in needs you: approve Duo or enter your password."
    case .busy: "Another sign-in is already in progress."
    }
  }
}
