#if os(iOS) && targetEnvironment(simulator) && CLIP_CLOUDKIT_REVIEW && CLIP_CLOUDKIT_SIM_SMOKE
import SwiftUI
import Foundation

@main struct CloudKitSimulatorSmokeApp: App {
    var body: some Scene {
        WindowGroup { SimulatorSmokeView() }
    }
}
private struct SimulatorSmokeView: View {
    @State private var lines: [String] = []
    @State private var started = false
    var body: some View {
        ScrollView {
            Text(verbatim: lines.joined(separator: "\n"))
                .font(.system(.body, design: .monospaced)).padding()
        }.task {
            guard !started else { return }
            started = true
            let args = ProcessInfo.processInfo.arguments
            let conflict = args.contains("--clip-simulator-conflict")
            let verify = args.contains("--clip-simulator-verify-resolution")
            let resultFile = conflict ? "cloudkit-conflict-result.txt" : (verify ? "cloudkit-resolution-result.txt" : "cloudkit-smoke-result.txt")
            func record(_ line: String) {
                lines.append(line)
                let url = URL.documentsDirectory.appending(path: resultFile)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
            }
            guard [args.contains("--clip-simulator-smoke"), conflict, verify].filter({ $0 }).count == 1,
                  ["com.ioant.clip.ios.simsmoke", "com.ioant.clip.ios"].contains(Bundle.main.bundleIdentifier ?? ""),
                  Bundle.main.object(forInfoDictionaryKey: "ClipCloudKitSmoke") as? String == "YES",
                  let config = CloudKitReviewConfiguration.current() else {
                record("RESULT: BLOCKED invalid explicit configuration"); return
            }
            do {
                if conflict { try await CloudKitCrossDeviceFixture.phoneConflict(config: config, log: record) }
                else if verify { try await CloudKitCrossDeviceFixture.phoneVerifyResolution(config: config, log: record) }
                else { try await CloudKitCrossDeviceFixture.runSimulator(config: config, log: record) }
                record("RESULT: PASS")
            } catch {
                let ns = error as NSError
                record("RESULT: FAIL " + ns.domain + " code " + String(ns.code))
            }
        }
    }
}
#endif
