import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // NOTA: o widget nativo de iOS (KairoWidgetBridge / KairoWidgetExtension)
    // existe no código mas NÃO está wired no projeto Xcode (nem o target da
    // extensão, nem o App Group). Enquanto não for integrado de verdade, não o
    // registramos aqui — senão o build quebra ("Cannot find KairoWidgetBridge").
    // O lado Dart (WidgetSync/MethodChannel 'kairo.widget') é best-effort e
    // apenas loga a ausência do handler no iOS.
  }
}
