import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      LocalSpeechBridge.shared.register(with: controller.binaryMessenger)
      LocalSetupBridge.shared.register(with: controller.binaryMessenger)
    }
    // A cold launch from the keyboard's 🎤 key arrives here, not in
    // openURLContexts.
    for context in connectionOptions.urlContexts {
      LocalSetupBridge.shared.handle(url: context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    for context in URLContexts {
      LocalSetupBridge.shared.handle(url: context.url)
    }
  }
}
