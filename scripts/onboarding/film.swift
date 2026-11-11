// Films an app's largest window, its rect on the display only, until stdin closes or FILM_MAX_SECONDS (default 60),
// with no pointer; H.264 at the display's scale, 60 fps. The backdrop (scripts/onboarding/backdrop.swift) shows
// through the app's glass. A capture that names the windows it takes draws glass over nothing (dark 33, light 241,
// where the screen shows 26 and 249 over black and white); one that leaves the other windows out draws it as the
// screen does. So this one leaves out every other app's window, and the desktop's lie under the backdrop. Prints
// "recording" with the film's first frame, and "intruder: …" when another app's window shows over the rect or under it
// above the backdrop (record-onboarding.sh then deletes the film). Usage: film <pid> <out.mp4> <backdrop's pid>
import AVFoundation
import ScreenCaptureKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let pid = pid_t(arguments[1]), let backdrop = pid_t(arguments[3]) else {
    FileHandle.standardError.write(Data("usage: film <pid> <out.mp4> <backdrop's pid>\n".utf8))
    exit(2)
}

final class Finished: NSObject, SCRecordingOutputDelegate {
    let done = DispatchSemaphore(value: 0)
    /// The caller times its steps from here: the first frame comes up to a second after the stream starts.
    func recordingOutputDidStartRecording(_: SCRecordingOutput) {
        print("recording")
        fflush(stdout)
    }

    func recordingOutputDidFinishRecording(_: SCRecordingOutput) {
        done.signal()
    }

    func recordingOutput(_: SCRecordingOutput, didFailWithError error: any Error) {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        done.signal()
    }
}

var content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
// A launching app: its first window comes within a few seconds.
for _ in 0 ..< 50 where !content.windows.contains(where: { $0.owningApplication?.processID == pid }) {
    try await Task.sleep(for: .milliseconds(200))
    content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
}

guard let app = content.applications.first(where: { $0.processID == pid }),
      let largest = content.windows.filter({ $0.owningApplication?.processID == pid })
          .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
      let display = content.displays.first(where: { $0.frame.intersects(largest.frame) })
else {
    FileHandle.standardError.write(Data("no window of pid \(pid)\n".utf8))
    exit(1)
}

// Every other window, those off screen too, so one that comes on screen stays out; a window made later is left out
// within a quarter of a second. Not the desktop's: with those left out the glass is drawn over nothing again (33).
let kept = Set([pid, backdrop])
func others(_ content: SCShareableContent) -> [SCWindow] {
    content.windows.filter { !kept.contains($0.owningApplication?.processID ?? 0) }
}

var left = try await others(SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false))
let filter = SCContentFilter(display: display, excludingWindows: left)
let config = SCStreamConfiguration()
// The window's rect only: the menu bar and the Dock are no part of the film.
config.sourceRect = largest.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
config.width = Int(largest.frame.width * CGFloat(filter.pointPixelScale))
config.height = Int(largest.frame.height * CGFloat(filter.pointPixelScale))
config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
config.captureResolution = .best
config.showsCursor = false
let stream = SCStream(filter: filter, configuration: config, delegate: nil)
let recording = SCRecordingOutputConfiguration()
recording.outputURL = URL(filePath: arguments[2])
recording.outputFileType = .mp4
recording.videoCodecType = .h264
let finished = Finished()
try stream.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: finished))
/// Another app's window the film could show: over the window's rect, or under the window above the backdrop (the glass
/// blurs it). Windows in front first.
func intruders() -> [String] {
    let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    func owner(_ window: [String: Any]) -> pid_t {
        window[kCGWindowOwnerPID as String] as? pid_t ?? 0
    }
    func crosses(_ window: [String: Any]) -> Bool {
        (window[kCGWindowBounds as String] as? NSDictionary)
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }?.intersects(largest.frame) == true
    }
    guard let filmed = list.firstIndex(where: { $0[kCGWindowNumber as String] as? CGWindowID == largest.windowID }),
          let under = list[filmed...].firstIndex(where: { owner($0) == backdrop })
    else { return ["no backdrop under the window"] }
    let above = list[..<filmed].filter { !known.contains($0[kCGWindowNumber as String] as? CGWindowID ?? 0) }
    return (above + list[filmed ..< under]).filter { !kept.contains(owner($0)) && crosses($0) }
        .map { $0[kCGWindowOwnerName as String] as? String ?? "a window" }
}

/// The windows over the rect now are left out of the film; only new ones count.
var known = Set(left.map(\.windowID))
try await stream.startCapture()
let limit = Double(ProcessInfo.processInfo.environment["FILM_MAX_SECONDS"] ?? "") ?? 60
let watch = Task {
    while !Task.isCancelled {
        for name in intruders() {
            print("intruder: \(name)")
            fflush(stdout)
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard let now = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            continue
        }
        let new = others(now).filter { !known.contains($0.windowID) }
        guard !new.isEmpty else { continue }
        known.formUnion(new.map(\.windowID))
        left += new
        try? await stream.updateContentFilter(SCContentFilter(display: display, excludingWindows: left))
    }
}

/// Stdin's end, or the limit, whichever comes first.
let stop = AsyncStream<Void> { done in
    Thread.detachNewThread {
        while readLine() != nil {}
        done.finish()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + limit) { done.finish() }
}

for await _ in stop {}
watch.cancel()
try? await stream.stopCapture()
// The delegate may report on the main queue, which a blocking wait here would hold. It often never reports, and the
// file is whole by then: 3 s at most.
for _ in 0 ..< 60 {
    if finished.done.wait(timeout: .now()) == .success {
        break
    }
    try await Task.sleep(for: .milliseconds(50))
}
