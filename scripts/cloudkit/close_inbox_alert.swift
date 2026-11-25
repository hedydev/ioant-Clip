import Foundation
import AppKit
import ApplicationServices

@main struct CloseInboxAlert {
    @MainActor static func main() throws {
        let expectedPath = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath().path
        let processes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.ioant.clip.macos").filter { !$0.isTerminated }
        if processes.isEmpty { print("Prior Clip process already stopped"); return }
        guard processes.count == 1, let app = processes.first,
              app.bundleURL?.resolvingSymlinksInPath().path == expectedPath else {
            throw NSError(domain: "UnexpectedClipProcess", code: 1)
        }
        guard AXIsProcessTrusted() else {
            throw NSError(domain: "AccessibilityUnavailable", code: 1)
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        func attr(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(node,key as CFString,&value) == .success ? value : nil
        }
        func str(_ node: AXUIElement, _ key: String) -> String? { attr(node,key) as? String }
        func children(_ node: AXUIElement,_ key: String = "AXChildren") -> [AXUIElement] {
            attr(node,key) as? [AXUIElement] ?? []
        }
        func nodes(_ node: AXUIElement, depth: Int = 0, budget: inout Int) -> [AXUIElement] {
            guard depth < 10, budget > 0 else { return [] }
            budget -= 1
            return [node] + children(node).flatMap { nodes($0,depth:depth+1,budget:&budget) }
        }
        let exactMessages = Set(["无法读取待导入的网页采集。","Unable to read pending web captures."])
        let exactButtons = Set(["确定","OK"])
        let deadline = Date().addingTimeInterval(15)
        var dismissed = 0
        while !app.isTerminated && Date() < deadline {
            let windows = children(root,"AXWindows")
            // Only inspect known alert containers; do not act on any other modal.
            var alerts: [AXUIElement] = windows.flatMap { children($0,"AXSheets") }
            alerts += windows.filter { str($0,"AXSubrole") == "AXDialog" || str($0,"AXSubrole") == "AXSystemDialog" || str($0,"AXRole") == "AXDialog" }
            for alert in alerts {
                var budget = 100
                let items = nodes(alert,budget:&budget)
                let match = items.contains { n in ["AXTitle","AXValue","AXDescription"].contains { k in str(n,k).map(exactMessages.contains) == true } }
                guard match else { continue }
                let buttons = items.filter { str($0,"AXRole") == "AXButton" && str($0,"AXTitle").map(exactButtons.contains) == true }
                guard buttons.count == 1 else { continue }
                if AXUIElementPerformAction(buttons[0],kAXPressAction as CFString) == .success { dismissed += 1 }
            }
            _ = app.terminate()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        print("Matched inbox alerts dismissed:",dismissed)
        guard app.isTerminated else { throw NSError(domain:"GracefulQuitNotConfirmed",code:1) }
        print("PASS: exact prior daily client gracefully stopped; no force termination")
    }
}
