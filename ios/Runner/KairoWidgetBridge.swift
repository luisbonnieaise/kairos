// KairoWidgetBridge.swift — lado iOS do MethodChannel('kairo.widget').
// O app Flutter chama `updateWidgetData`; aqui gravamos no App Group e
// recarregamos as timelines (reload imediato, fora da cadência horária).
//
// Registrar em AppDelegate.didInitializeImplicitFlutterEngine:
//   KairoWidgetBridge.register(with: engineBridge.pluginRegistry)
// (ver AppDelegate.swift)

import Flutter
import WidgetKit

enum KairoWidgetBridge {
    static let channelName = "kairo.widget"
    static let appGroup = "group.com.kairo.shared"

    static func register(with registry: FlutterPluginRegistry) {
        guard let messenger = (registry.registrar(forPlugin: "KairoWidgetBridge"))?.messenger() else { return }
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "updateWidgetData":
                handleUpdate(call.arguments, result: result)
            case "reloadWidgets":
                reloadAll()
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func handleUpdate(_ args: Any?, result: FlutterResult) {
        guard let map = args as? [String: Any],
              let defaults = UserDefaults(suiteName: appGroup) else {
            result(false)
            return
        }
        if let v = map["phrase_today"] as? String { defaults.set(v, forKey: "phrase_today") }
        if let v = map["next_practice_title"] as? String { defaults.set(v, forKey: "next_practice_title") }
        // next_practice_time pode vir String (ISO8601) ou nil.
        if map["next_practice_time"] is NSNull || map["next_practice_time"] == nil {
            defaults.removeObject(forKey: "next_practice_time")
        } else if let v = map["next_practice_time"] as? String {
            defaults.set(v, forKey: "next_practice_time")
        }
        if let v = map["streak_count"] as? Int { defaults.set(v, forKey: "streak_count") }
        defaults.set(Date().timeIntervalSince1970, forKey: "last_updated")

        reloadAll()
        result(true)
    }

    private static func reloadAll() {
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
