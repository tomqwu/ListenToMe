import SwiftUI

/// Simulator UI journeys set their text size explicitly. UIKit can retain a prior process's
/// accessibility-size override despite new launch arguments; that must not change the next test.
/// Normal launches and every release/device build continue to use the user's system setting.
struct MobileUITestTextSize: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["LISTENTOME_UI_TESTS"] == "1" {
            content.dynamicTypeSize(Self.requestedSize)
        } else {
            content
        }
        #else
        content
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    private static var requestedSize: DynamicTypeSize {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-UIPreferredContentSizeCategoryName"),
              arguments.indices.contains(index + 1) else { return .large }
        switch arguments[index + 1] {
        case "UICTContentSizeCategoryXS": return .xSmall
        case "UICTContentSizeCategoryS": return .small
        case "UICTContentSizeCategoryM": return .medium
        case "UICTContentSizeCategoryXL": return .xLarge
        case "UICTContentSizeCategoryXXL": return .xxLarge
        case "UICTContentSizeCategoryXXXL": return .xxxLarge
        case "UICTContentSizeCategoryAccessibilityM": return .accessibility1
        case "UICTContentSizeCategoryAccessibilityL": return .accessibility2
        case "UICTContentSizeCategoryAccessibilityXL": return .accessibility3
        case "UICTContentSizeCategoryAccessibilityXXL": return .accessibility4
        case "UICTContentSizeCategoryAccessibilityXXXL": return .accessibility5
        default: return .large
        }
    }
    #endif
}
