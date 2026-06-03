// KairoWidgetBundle.swift — ponto de entrada (@main) da Widget Extension.
// Lock screen só entra em iOS 16+ (degrada graciosamente em iOS 15).

import WidgetKit
import SwiftUI

@main
struct KairoWidgetBundle: WidgetBundle {
    var body: some Widget {
        KairoSmallWidget()
        KairoLargeWidget()
        if #available(iOSApplicationExtension 16.0, *) {
            KairoLockRectangularWidget()
            KairoLockInlineWidget()
            KairoLockCircularWidget()
        }
    }
}
