@preconcurrency import AVFoundation
import AppKit
import SwiftUI

@MainActor final class MirrorService: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var starting = false
    @Published var error: String?
    @Published private(set) var devices: [AVCaptureDevice] = []
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.nexa.camera", qos: .userInitiated)
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    init() {
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop(); self?.error = "Camera unavailable. Close other camera apps and try again." }
            })
        }
    }
    func refreshDevices() {
        devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
    }
    func toggle(deviceID: String) {
        if active || starting { stop() } else { Task { await start(deviceID: deviceID) } }
    }
    func start(deviceID: String) async {
        guard !starting, !active else { return }
        generation += 1; let token = generation; starting = true; error = nil
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var allowed = status == .authorized
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        guard generation == token else { return }
        guard allowed else { starting = false; error = "Allow Camera access for Nexa in System Settings → Privacy & Security → Camera."; return }
        refreshDevices()
        guard let device = devices.first(where: { $0.uniqueID == deviceID }) ?? devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? devices.first else { starting = false; error = "Connect a camera to use Mirror."; return }
        let session = self.session
        queue.async { [weak self] in
            do {
                let input = try AVCaptureDeviceInput(device: device)
                session.beginConfiguration()
                session.inputs.forEach { session.removeInput($0) }
                session.sessionPreset = .medium
                guard session.canAddInput(input) else { session.commitConfiguration(); throw NexaError.message("This camera cannot be opened right now.") }
                session.addInput(input); session.commitConfiguration(); session.startRunning()
                let running = session.isRunning
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.starting = false; self.active = running
                    if !running { self.error = "The camera did not start. Try another camera." }
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in guard let self, self.generation == token else { return }; self.starting = false; self.error = message }
            }
        }
    }
    func stop() {
        generation += 1; active = false; starting = false
        let session = self.session
        queue.async {
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration(); session.inputs.forEach { session.removeInput($0) }; session.commitConfiguration()
        }
    }
}

private final class MirrorPreview: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor; preview.videoGravity = .resizeAspectFill; layer?.addSublayer(preview) }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); preview.frame = bounds
        if let connection = preview.connection, connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = true }
        CATransaction.commit()
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView { let view = MirrorPreview(); view.preview.session = session; return view }
    func updateNSView(_ view: NSView, context: Context) { (view as? MirrorPreview)?.preview.session = session; view.needsLayout = true }
    static func dismantleNSView(_ view: NSView, coordinator: ()) { (view as? MirrorPreview)?.preview.session = nil }
}

struct MirrorWidget: View {
    @ObservedObject var service: MirrorService
    @ObservedObject var preferences: PreferencesStore
    var size: CGFloat = 102
    var body: some View {
        VStack(spacing: 8) {
            Button { service.toggle(deviceID: preferences.value.cameraDeviceID) } label: {
                ZStack {
                    Circle().fill(.white.opacity(0.095))
                    if service.active { CameraPreview(session: service.session).clipShape(Circle()).allowsHitTesting(false) }
                    else if service.starting { ProgressView().controlSize(.small) }
                    else { VStack(spacing: 7) { Image(systemName: "web.camera").font(.system(size: 25, weight: .medium)); Text("Mirror").font(.system(size: 12, weight: .medium)) }.foregroundStyle(.white.opacity(0.6)) }
                }.frame(width: size, height: size).overlay(Circle().strokeBorder(.white.opacity(0.07)))
            }.buttonStyle(NotchButtonStyle()).help(service.active ? "Turn camera off" : "Turn camera mirror on").accessibilityLabel(service.active ? "Stop camera mirror" : "Start camera mirror")
            if service.active { Label("Camera on · tap to stop", systemImage: "circle.fill").font(.system(size: 8)).foregroundStyle(preferences.value.accent.color) }
            else if service.error != nil { Text("Camera needs attention").font(.system(size: 9)).foregroundStyle(.orange).help(service.error ?? "") }
        }
    }
}

struct MirrorView: View {
    @ObservedObject var service: MirrorService
    @ObservedObject var preferences: PreferencesStore
    var body: some View {
        VStack(spacing: 15) {
            MirrorWidget(service: service, preferences: preferences, size: 180)
            Picker("Camera", selection: $preferences.value.cameraDeviceID) {
                Text("Automatic").tag("")
                ForEach(service.devices, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
            }.frame(maxWidth: 300).onChange(of: preferences.value.cameraDeviceID) { _, _ in service.stop() }
            Text("A live mirror, only while open. No photos, recordings or microphone.").font(.system(size: 11)).foregroundStyle(NexaStyle.secondary)
            InlineError(text: service.error)
        }.frame(maxWidth: .infinity).onAppear { service.refreshDevices() }
    }
}
