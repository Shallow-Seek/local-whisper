import Flutter
import UIKit

/// The app group shared with the keyboard extension. AltStore and SideStore
/// rename app groups when they re-sign the app (appending the team ID) and
/// record the new names under `ALTAppGroups` in Info.plist, so prefer those
/// and fall back to the group this project declares.
enum SharedAppGroup {
  static let declared = "group.info.gabrimatic.localWhisperFlutter"

  static let identifier: String = {
    let candidates =
      (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []) + [declared]
    return candidates.first {
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
    } ?? declared
  }()
}

final class LocalSetupBridge: NSObject {
  static let shared = LocalSetupBridge()

  private let appGroup = SharedAppGroup.identifier
  private var didRegister = false
  private var channel: FlutterMethodChannel?
  /// Request id from a keyboard 🎤 tap that Flutter has not picked up yet.
  private var pendingDictationId: String?

  /// Handles `localwhisper://dictate?id=<request>` opened by the keyboard.
  @discardableResult
  func handle(url: URL) -> Bool {
    guard url.scheme == "localwhisper", url.host == "dictate" else { return false }
    let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first { $0.name == "id" }?.value
    guard let id, !id.isEmpty else { return false }
    pendingDictationId = id
    channel?.invokeMethod("dictationRequested", arguments: nil)
    return true
  }

  func register(with messenger: FlutterBinaryMessenger) {
    guard !didRegister else { return }
    didRegister = true
    let method = FlutterMethodChannel(name: "local_whisper/setup", binaryMessenger: messenger)
    channel = method
    method.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        return result(FlutterError(code: "released", message: "Setup bridge released", details: nil))
      }
      switch call.method {
      case "openKeyboardSettings", "openAppSettings":
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          return result(false)
        }
        UIApplication.shared.open(url) { opened in
          result(opened)
        }
      case "keyboardStatus":
        result(self.keyboardStatusPayload())
      case "markKeyboardSeen":
        self.markKeyboardOpened()
        result(nil)
      case "syncKeyboardSettings":
        let args = call.arguments as? [String: Any]
        self.syncKeyboardSettings(
          haptics: args?["haptics"] as? Bool ?? true,
          quickInsert: args?["quickInsert"] as? Bool ?? true
        )
        result(nil)
      case "takePendingDictation":
        result(self.pendingDictationId)
        self.pendingDictationId = nil
      case "completeDictation":
        let args = call.arguments as? [String: Any]
        self.completeDictation(
          id: args?["id"] as? String ?? "",
          text: args?["text"] as? String ?? ""
        )
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func syncKeyboardSettings(haptics: Bool, quickInsert: Bool) {
    guard let defaults = UserDefaults(suiteName: appGroup) else { return }
    defaults.set(haptics, forKey: "keyboard.haptics")
    defaults.set(quickInsert, forKey: "keyboard.quickInsert")
    defaults.synchronize()
  }

  /// Leaves the transcript where the keyboard picks it up when the user
  /// returns to the app they were typing in.
  private func completeDictation(id: String, text: String) {
    guard !id.isEmpty else { return }
    // Also on the pasteboard, tagged with the request id, so the keyboard
    // still gets the text if re-signing left the app group unshared.
    UIPasteboard.general.setItems([[
      "public.utf8-plain-text": text,
      "info.gabrimatic.localwhisper.dictation-id": Data(id.utf8),
    ]])
    guard let defaults = UserDefaults(suiteName: appGroup) else { return }
    defaults.set(text, forKey: "dictation.resultText")
    defaults.set(id, forKey: "dictation.resultId")
    defaults.synchronize()
  }

  private func markKeyboardOpened() {
    guard let defaults = UserDefaults(suiteName: appGroup) else { return }
    defaults.set(Date().timeIntervalSince1970, forKey: "keyboard.lastOpenedAt")
    defaults.synchronize()
  }

  private func keyboardStatusPayload() -> [String: Any] {
    guard let defaults = UserDefaults(suiteName: appGroup) else {
      return [
        "keyboardSeen": false,
        "message": "Keyboard status is unavailable because the app group could not be opened.",
      ]
    }
    let lastOpened = defaults.double(forKey: "keyboard.lastOpenedAt")
    let seen = lastOpened > 0
    return [
      "keyboardSeen": seen,
      "message": seen
        ? "Local Whisper Keyboard was opened and verified."
        : "Keyboard has not been verified yet. Add it in Settings, switch to it in the practice field, then tap Verify on the keyboard.",
    ]
  }
}
