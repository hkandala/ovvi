// Films an app's largest window, its rect on the display, until stdin closes: only that app's windows
// (ScreenCaptureKit), never another app's, the desktop or the pointer; H.264 at the display's scale, 60 fps.
// The backdrop (scripts/onboarding/backdrop.swift) shows through the app's glass: a capture that names
// the windows it takes draws glass over nothing (dark 33, light 241 where the screen shows 26 and 249 over black and
// white); one that names the windows it leaves out draws the glass as the screen does. It stops by itself after
// FILM_MAX_SECONDS (default 60), whatever its caller does. Usage: film <pid> <out.mp4> <backdrop's pid>
import AVFoundation
import ScreenCaptureKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let pid = pid_t(arguments[1]), let backdrop = pid_t(arguments[3]) else {
    FileHandle.standardError.write(Data("usage: film <pid> <out.mp4> <backdrop's pid>\n".utf8))
    exit(2)
}

final class Finished: NSObject, SCRecordingOutputDelegate {
    let done = DispatchSemaphore(value: 0)
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
// within a quarter of a second, and marks the film (record-onboarding.sh deletes it). Not the desktop's: with those
// left out the glass is drawn over nothing again (33), and they lie under the backdrop.
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
try await stream.startCapture()
print("recording")
fflush(stdout)
let limit = Double(ProcessInfo.processInfo.environment["FILM_MAX_SECONDS"] ?? "") ?? 60
let watch = Task {
    var known = Set(left.map(\.windowID))
    while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        guard let now = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            continue
        }
        let new = others(now).filter { !known.contains($0.windowID) }
        guard !new.isEmpty else { continue }
        known.formUnion(new.map(\.windowID))
        left += new
        try? await stream.updateContentFilter(SCContentFilter(display: display, excludingWindows: left))
        // Only a window over the filmed one can show in its rect: under it is the backdrop.
        let list = CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, largest.windowID) as? [[String: Any]] ?? []
        let above = Set(list
            .filter { ($0[kCGWindowAlpha as String] as? Double ?? 0) > 0.01 }
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        for window in new where above.contains(window.windowID) && window.frame.intersects(largest.frame) {
            print("intruder: \(window.owningApplication?.applicationName ?? "a window") over the film")
            fflush(stdout)
        }
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
for _ in 0 ..< 60 where finished.done.wait(timeout: .now()) == .timedOut {
    try await Task.sleep(for: .milliseconds(50))
}
