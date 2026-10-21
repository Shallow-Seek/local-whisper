import UIKit

/// The app group shared with Local Whisper. AltStore and SideStore rename app
/// groups when they re-sign (appending the team ID) and record the new names
/// under `ALTAppGroups` in Info.plist; read the extension's own and the
/// containing app's, then fall back to the group this project declares.
private enum SharedAppGroup {
  static let declared = "group.info.gabrimatic.localWhisperFlutter"

  static let identifier: String = {
    let containingApp = Bundle(
      url: Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
    )
    let renamed = [Bundle.main, containingApp]
      .compactMap { $0?.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] }
      .flatMap { $0 }
    return (renamed + [declared]).first {
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
    } ?? declared
  }()
}

final class KeyboardViewController: UIInputViewController {
  private let appGroup = SharedAppGroup.identifier
  private let verificationToken = "[[LOCAL_WHISPER_KEYBOARD_VERIFIED]]"
  private let idleSubtitle = "offline dictation"
  private let subtitle = UILabel()
  private var dictationPoll: Timer?
  private var dictationPollStartedAt = Date()
  /// Pasteboard type the app tags its transcript with, holding the request
  /// id. Used when the app group turns out not to be shared after re-signing.
  private let dictationIdType = "info.gabrimatic.localwhisper.dictation-id"
  private let accent = UIColor(red: 117 / 255, green: 227 / 255, blue: 190 / 255, alpha: 1.0)
  private let panel = UIColor(red: 22 / 255, green: 26 / 255, blue: 29 / 255, alpha: 1.0)
  private let surface = UIColor(red: 44 / 255, green: 50 / 255, blue: 57 / 255, alpha: 1.0)
  private let raised = UIColor(red: 58 / 255, green: 66 / 255, blue: 74 / 255, alpha: 1.0)
  private var hapticsEnabled: Bool {
    UserDefaults(suiteName: appGroup)?.object(forKey: "keyboard.haptics") as? Bool ?? true
  }
  private var quickInsertEnabled: Bool {
    UserDefaults(suiteName: appGroup)?.object(forKey: "keyboard.quickInsert") as? Bool ?? true
  }

  override func loadView() {
    let keyboardView = UIInputView(frame: .zero, inputViewStyle: .keyboard)
    keyboardView.allowsSelfSizing = true
    view = keyboardView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = panel
    view.isOpaque = true
    view.clipsToBounds = true
    buildKeyboard()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Inserting from viewWillAppear can run before the host text field is
    // attached again, and the text is silently dropped. Poll from here on.
    if pendingDictationId != nil {
      subtitle.text = "Waiting for text from Local Whisper…"
      startDictationPoll()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopDictationPoll()
  }

  override func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
    insertFinishedDictation()
  }

  private func buildKeyboard() {
    let root = UIStackView()
    root.axis = .vertical
    root.spacing = 6
    root.translatesAutoresizingMaskIntoConstraints = false
    root.layoutMargins = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
    root.isLayoutMarginsRelativeArrangement = true

    root.addArrangedSubview(actionRow())
    root.addArrangedSubview(buttonRow([
      key("Clean", action: #selector(insertCleanMarker), style: .mode),
      key("Message", action: #selector(insertMessageMarker), style: .mode),
      key("Notes", action: #selector(insertNotesMarker), style: .mode),
      key("Prompt", action: #selector(insertPromptMarker), style: .mode),
    ]))
    if quickInsertEnabled {
      root.addArrangedSubview(buttonRow([
        key(",", text: ", "),
        key(".", text: ". "),
        key("?", text: "? "),
        key("!", text: "! "),
        key("return", text: "\n"),
      ]))
    }
    let bottomButtons = needsInputModeSwitchKey
      ? [
        key("next", action: #selector(advanceKeyboard), style: .utility),
        key("space", text: " ", weight: 2.6),
        key("delete", action: #selector(deleteBackward), style: .utility),
      ]
      : [
        key("space", text: " ", weight: 2.6),
        key("delete", action: #selector(deleteBackward), style: .utility),
      ]
    root.addArrangedSubview(weightedButtonRow(bottomButtons))

    view.addSubview(root)
    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      root.topAnchor.constraint(equalTo: view.topAnchor),
      root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      view.heightAnchor.constraint(equalToConstant: quickInsertEnabled ? 196 : 152),
    ])
  }

  private func actionRow() -> UIStackView {
    let title = UILabel()
    title.text = "Local Whisper"
    title.font = .systemFont(ofSize: 14, weight: .semibold)
    title.textColor = .white

    subtitle.text = idleSubtitle
    subtitle.font = .systemFont(ofSize: 10, weight: .medium)
    subtitle.textColor = UIColor.white.withAlphaComponent(0.66)
    subtitle.adjustsFontSizeToFitWidth = true
    subtitle.minimumScaleFactor = 0.82
    subtitle.numberOfLines = 2

    let labels = UIStackView(arrangedSubviews: [title, subtitle])
    labels.axis = .vertical
    labels.spacing = 2
    labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let dictateButton = key("🎤 Dictate", action: #selector(startDictation), style: .accent)
    dictateButton.accessibilityLabel = "Dictate"
    dictateButton.widthAnchor.constraint(equalToConstant: 112).isActive = true
    let verifyButton = key("Verify", action: #selector(verifySetup), style: .utility)
    verifyButton.widthAnchor.constraint(equalToConstant: 60).isActive = true

    let row = UIStackView(arrangedSubviews: [labels, dictateButton, verifyButton])
    row.axis = .horizontal
    row.alignment = .center
    row.distribution = .fill
    row.spacing = 8
    return row
  }

  private func buttonRow(_ buttons: [UIButton]) -> UIStackView {
    let row = UIStackView(arrangedSubviews: buttons)
    row.axis = .horizontal
    row.distribution = .fillEqually
    row.spacing = 6
    return row
  }

  private func weightedButtonRow(_ buttons: [UIButton]) -> UIStackView {
    let row = UIStackView(arrangedSubviews: buttons)
    row.axis = .horizontal
    row.distribution = .fillProportionally
    row.spacing = 6
    return row
  }

  private enum KeyStyle {
    case normal
    case mode
    case utility
    case accent
  }

  private func key(
    _ title: String,
    text: String? = nil,
    action: Selector? = nil,
    style: KeyStyle = .normal,
    weight: CGFloat = 1
  ) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(
      ofSize: title.count > 7 ? 12 : 14,
      weight: style == .accent ? .bold : .semibold
    )
    button.titleLabel?.adjustsFontSizeToFitWidth = true
    button.titleLabel?.minimumScaleFactor = 0.75
    button.setTitleColor(style == .accent ? .black : .white, for: .normal)
    button.backgroundColor = switch style {
    case .accent:
      accent
    case .utility:
      raised
    case .mode, .normal:
      surface
    }
    button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
    button.layer.cornerRadius = 7
    button.layer.cornerCurve = .continuous
    button.heightAnchor.constraint(equalToConstant: style == .accent ? 34 : 38).isActive = true
    button.accessibilityLabel = title
    if let text {
      button.accessibilityValue = text
      button.addTarget(self, action: #selector(insertButtonText(_:)), for: .touchUpInside)
    } else if let action {
      button.addTarget(self, action: action, for: .touchUpInside)
    }
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 37 * weight).isActive = true
    return button
  }

  private func tapFeedback() {
    guard hapticsEnabled else { return }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  @objc private func insertCleanMarker() {
    tapFeedback()
    textDocumentProxy.insertText("[Clean] ")
  }

  @objc private func insertButtonText(_ sender: UIButton) {
    guard let text = sender.accessibilityValue else { return }
    tapFeedback()
    textDocumentProxy.insertText(text)
  }

  @objc private func insertMessageMarker() {
    tapFeedback()
    textDocumentProxy.insertText("[Message] ")
  }

  @objc private func insertNotesMarker() {
    tapFeedback()
    textDocumentProxy.insertText("[Notes]\n")
  }

  @objc private func insertPromptMarker() {
    tapFeedback()
    textDocumentProxy.insertText("[Prompt] ")
  }

  @objc private func deleteBackward() {
    tapFeedback()
    textDocumentProxy.deleteBackward()
  }

  @objc private func advanceKeyboard() {
    advanceToNextInputMode()
  }

  // MARK: Dictation
  //
  // Keyboards cannot use the microphone, so 🎤 opens Local Whisper with a
  // request id. The app records, transcribes, and leaves the text in the
  // shared app group under that id; when the user taps ◀ back to this app,
  // the keyboard inserts it.

  private var sharedDefaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  private var pendingDictationId: String? {
    sharedDefaults?.string(forKey: "dictation.requestId")
  }

  @objc private func startDictation() {
    tapFeedback()
    guard hasFullAccess, let defaults = sharedDefaults else {
      subtitle.text = "Allow Full Access in Settings to dictate"
      return
    }
    let id = UUID().uuidString
    defaults.removeObject(forKey: "dictation.resultId")
    defaults.removeObject(forKey: "dictation.resultText")
    defaults.set(id, forKey: "dictation.requestId")
    defaults.synchronize()
    guard let url = URL(string: "localwhisper://dictate?id=\(id)"), openContainingApp(url) else {
      subtitle.text = "Open Local Whisper to dictate"
      return
    }
    subtitle.text = "Speak in Local Whisper, then tap ◀"
    startDictationPoll()
  }

  /// Inserts the transcript for the pending request once the app has left it.
  private func insertFinishedDictation() {
    guard
      isViewLoaded, view.window != nil,
      let defaults = sharedDefaults,
      let id = defaults.string(forKey: "dictation.requestId"),
      let text = finishedDictationText(for: id, defaults: defaults)
    else { return }
    defaults.removeObject(forKey: "dictation.requestId")
    defaults.removeObject(forKey: "dictation.resultId")
    defaults.removeObject(forKey: "dictation.resultText")
    defaults.synchronize()
    stopDictationPoll()
    subtitle.text = idleSubtitle
    textDocumentProxy.insertText(text)
  }

  private func finishedDictationText(for id: String, defaults: UserDefaults) -> String? {
    if defaults.string(forKey: "dictation.resultId") == id,
      let text = defaults.string(forKey: "dictation.resultText")
    {
      return text
    }
    // The app also puts the transcript on the pasteboard, tagged with the
    // request id, in case the app group is not shared between the two.
    let pasteboard = UIPasteboard.general
    guard
      pasteboard.contains(pasteboardTypes: [dictationIdType]),
      let tag = pasteboard.data(forPasteboardType: dictationIdType),
      String(decoding: tag, as: UTF8.self) == id
    else { return nil }
    return pasteboard.string
  }

  /// Checks for the transcript while the keyboard is visible, in case it
  /// arrives after the user is already back (transcription still running).
  private func startDictationPoll() {
    stopDictationPoll()
    dictationPollStartedAt = Date()
    dictationPoll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self else { return }
      let waited = Date().timeIntervalSince(self.dictationPollStartedAt)
      if waited > 600 {
        self.stopDictationPoll()
        return
      }
      self.insertFinishedDictation()
      if waited > 15, self.dictationPoll != nil, self.view.window != nil {
        // Shown so a failed handoff can be told apart from a slow one.
        self.subtitle.text = "No text yet · \(self.appGroup)"
      }
    }
  }

  private func stopDictationPoll() {
    dictationPoll?.invalidate()
    dictationPoll = nil
  }

  /// `UIApplication.shared` is unavailable to extensions, so find the
  /// application through the responder chain and call
  /// `open(_:options:completionHandler:)` through the Objective-C runtime.
  private func openContainingApp(_ url: URL) -> Bool {
    typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let current = responder {
      if current is UIApplication,
        let method = class_getInstanceMethod(type(of: current), selector)
      {
        let open = unsafeBitCast(method_getImplementation(method), to: OpenURL.self)
        open(current, selector, url as NSURL, NSDictionary(), nil)
        return true
      }
      responder = current.next
    }
    return false
  }

  @objc private func verifySetup() {
    tapFeedback()
    textDocumentProxy.insertText(verificationToken)
  }
}
