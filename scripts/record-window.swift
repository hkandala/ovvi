// Films the welcome panel of an app until stdin closes: the rect Welcome.swift puts it in (960 x 640 pt, scaled to 80%
// of a smaller screen, in the middle of the main screen's visible area) plus 32 pt, on a gray backdrop, H.264 at the
// screen's scale, 60 fps. Only the windows the app makes after the start are drawn (the panel, from its first frame):
// never one that was there (the app's main window neither), another app's, the desktop or the pointer; the panel's
// glass still blurs what is behind it on screen.
// Usage: record-window <pid> <out.mp4>
import AppKit
import ScreenCaptureKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = pid_t(arguments[1]) else {
    FileHandle.standardError.write(Data("usage: record-window <pid> <out.mp4>\n".utf8))
    exit(2)
}

let out = URL(filePath: arguments[2])
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: out)

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data("\(text)\n".utf8))
    exit(1)
}

final class Delegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    let (ended, end) = AsyncStream<Void>.makeStream()
    func recordingOutputDidFinishRecording(_: SCRecordingOutput) {
        end.finish()
    }

    func recordingOutput(_: SCRecordingOutput, didFailWithError error: any Error) {
        fail("the film failed: \(error)")
    }

    func stream(_: SCStream, didStopWithError error: any Error) {
        fail("the stream stopped: \(error)")
    }
}

guard let screen = NSScreen.main else { fail("no screen") }
let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
guard let display = content.displays.first(where: { $0.displayID == number }),
      let app = content.applications.first(where: { $0.processID == pid }) else { fail("no display or app \(pid)") }
// As Welcome.swift places the panel, in the display's top-left points.
let visible = screen.visibleFrame, full = screen.frame
let scale = min(1, 0.8 * visible.width / 960, 0.8 * visible.height / 640)
let size = CGSize(width: 960 * scale, height: 640 * scale)
let panel = CGRect(x: (visible.midX - size.width / 2).rounded() - full.minX,
                   y: full.maxY - (visible.midY - size.height / 2).rounded() - size.height, width: size.width,
                   height: size.height)
let rect = panel.insetBy(dx: -32, dy: -32).intersection(CGRect(origin: .zero, size: full.size))
// Its normal windows only: a closing menu's window in the list stopped the stream once it closed.
let filter = SCContentFilter(display: display, including: [app], exceptingWindows: content.windows.filter {
    $0.owningApplication?.processID == pid && $0.windowLayer == 0
})
/// Kept for the run: the configuration does not retain it.
let backdrop = CGColor(gray: 0.5, alpha: 1)
let config = SCStreamConfiguration()
config.sourceRect = rect
// Even pixel sizes: H.264 needs them.
config.width = Int(rect.width * screen.backingScaleFactor) / 2 * 2
config.height = Int(rect.height * screen.backingScaleFactor) / 2 * 2
config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
config.captureResolution = .best
config.showsCursor = false
config.backgroundColor = backdrop
let delegate = Delegate()
let stream = SCStream(filter: filter, configuration: config, delegate: delegate)
let recording = SCRecordingOutputConfiguration()
recording.outputURL = out
recording.outputFileType = .mp4
recording.videoCodecType = .h264
try stream.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: delegate))

/// In an async function, so the async start and stop are the ones called (top-level code took the handler forms).
func capture(_ start: Bool) async throws {
    if start {
        try await stream.startCapture()
    } else {
        try await stream.stopCapture()
    }
}

let level = Int(CGWindowLevelForKey(.floatingWindow))
func shown() async -> SCWindow? {
    let windows = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true).windows
    return windows?.first { $0.owningApplication?.processID == pid && $0.windowLayer == level }
}

try await capture(true)
// The film is for the panel's first frames: it must not be there yet.
if await shown() != nil {
    fail("the panel showed before the recording")
}

print("recording")
fflush(stdout)

// Never filming on after the app: a test that quit it without a stop.
Task.detached {
    while kill(pid, 0) == 0 {
        try? await Task.sleep(for: .seconds(2))
    }
    fail("the app (pid \(pid)) quit while filming")
}

/// Where the panel showed, to check the film framed it.
nonisolated(unsafe) var frame: CGRect? // set by the poll only, read after it ends
let poll = Task {
    while !Task.isCancelled {
        if let window = await shown() {
            frame = window.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            return
        }
        try? await Task.sleep(for: .milliseconds(100))
    }
}

// Off the main actor, which the poll needs.
await Task.detached { while readLine() != nil {} }.value
poll.cancel()
_ = await poll.value
try await capture(false)
for await _ in delegate.ended {}
guard let frame else { fail("no panel of pid \(pid) showed") }
guard rect.contains(frame) else { fail("the panel showed at \(frame), outside the film's \(rect)") }
