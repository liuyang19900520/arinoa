import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var vm = BeautyViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickerItem: PhotosPickerItem?
    @State private var panel = Panel.none
    @State private var beautyItem = BeautyItem.smooth
    @State private var showSettings = false

    // Preview gestures
    @State private var pressStart: CGPoint?
    @State private var longPressTask: Task<Void, Never>?
    @State private var longPressFired = false
    @State private var pinchBase: CGFloat?
    @State private var biasBase: Float?

    enum Panel { case none, beauty, filter }

    enum BeautyItem: String, CaseIterable {
        case smooth = "磨皮", whiten = "美白", eyes = "大眼", slim = "瘦脸"
        var icon: String {
            switch self {
            case .smooth: "drop"
            case .whiten: "sun.max"
            case .eyes: "eye"
            case .slim: "face.smiling"
            }
        }
        var key: WritableKeyPath<BeautyParams, Float> {
            switch self {
            case .smooth: \.smooth
            case .whiten: \.whiten
            case .eyes: \.eyes
            case .slim: \.slim
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                // An overlay doesn't take part in layout, so a full-screen 9:16 preview (taller than
                // the safe area) can't push the controls off-screen.
                Color.clear
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(alignment: .top) { preview(in: geo) }
                VStack(spacing: 0) {
                    topBar
                    recordingTime
                    Spacer()
                    if let toast = vm.toast {
                        Text(toast).font(.footnote).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.6), in: Capsule()).foregroundStyle(.white)
                            .task(id: toast) { try? await Task.sleep(for: .seconds(2)); vm.toast = nil }
                            .padding(.bottom, 12)
                    }
                    switch panel {
                    case .none: EmptyView()
                    case .beauty: beautyPanel.transition(.move(edge: .bottom).combined(with: .opacity))
                    case .filter: filterPanel.transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    bottomBar
                }
                if vm.screenFlash {
                    Color.white.ignoresSafeArea().allowsHitTesting(false)
                }
            }
        }
        .statusBarHidden(vm.screenFlash)
        .onChange(of: pickerItem) { _, item in Task { await vm.load(item) } }
        .task { await vm.loadDemoIfRequested() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { vm.appBecameActive() }
            if phase == .background { vm.appEnteredBackground() }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }

    // MARK: - Preview

    /// 9:16 fills the screen; 3:4 and 1:1 sit under the top bar like Apple Camera.
    @ViewBuilder private func preview(in geo: GeometryProxy) -> some View {
        let full = vm.previewAspect < 0.6 || vm.photoMode
        let width = geo.size.width
        let height = full ? geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom : width / vm.previewAspect
        let top: CGFloat = full ? -geo.safeAreaInsets.top
            : 44 + (vm.aspect == .r1x1 ? (width * 4 / 3 - width) / 2 : 0)
        let size = CGSize(width: width, height: height)

        ZStack {
            MetalPreview(renderer: vm.renderer, onCaptureEvent: { vm.shutter() })
            if vm.grid && !vm.photoMode { GridOverlay() }
            if let mark = vm.focusMark { focusBox(mark) }
            if vm.shutterBlink { Color.black.opacity(0.6) }
            if let n = vm.countdown {
                Text("\(n)").font(.system(size: 120, weight: .thin)).foregroundStyle(.white).shadow(radius: 6)
            }
            if !vm.photoMode, let status = vm.cameraStatus { statusView(status) }
        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .gesture(pressGesture(size: size))
        .simultaneousGesture(pinchGesture)
        .overlay(alignment: .top) {
            if vm.focusMark?.locked == true {
                Text("AE/AF 锁定").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.yellow, in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.black)
                    .padding(.top, full ? geo.safeAreaInsets.top + 52 : 8)
            }
        }
        .offset(y: top)
        .animation(.snappy, value: vm.previewAspect)
    }

    /// Tap = focus/expose at point, hold 0.6 s = AE/AF lock. Tapping while a panel is open closes it.
    private func pressGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if pressStart == nil {
                    pressStart = v.location
                    longPressFired = false
                    longPressTask = Task {
                        try? await Task.sleep(for: .milliseconds(600))
                        guard !Task.isCancelled, pinchBase == nil, panel == .none, !vm.tapToShoot else { return }
                        longPressFired = true
                        vm.focus(at: v.location, in: size, lock: true)
                    }
                } else if let s = pressStart, hypot(v.location.x - s.x, v.location.y - s.y) > 12 {
                    longPressTask?.cancel()
                }
            }
            .onEnded { v in
                longPressTask?.cancel()
                defer { pressStart = nil }
                guard !longPressFired, pinchBase == nil, let s = pressStart,
                      hypot(v.location.x - s.x, v.location.y - s.y) <= 12 else { return }
                if panel != .none {
                    withAnimation(.snappy) { panel = .none }
                } else {
                    vm.previewTapped(at: v.location, in: size)
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if pinchBase == nil { pinchBase = vm.zoom; longPressTask?.cancel() }
                vm.setZoom((pinchBase ?? 1) * v.magnification)
            }
            .onEnded { _ in
                // Keep pinchBase set briefly so the lifting finger isn't read as a tap.
                Task { try? await Task.sleep(for: .milliseconds(150)); pinchBase = nil }
            }
    }

    /// Yellow focus square with the ☀︎ exposure handle; drag the handle up/down to brighten/darken.
    private func focusBox(_ mark: FocusMark) -> some View {
        let side: CGFloat = 76
        let handleY = CGFloat(-vm.exposureBias) * 18
        return ZStack {
            Rectangle().strokeBorder(Color.yellow, lineWidth: 1.2).frame(width: side, height: side)
            Image(systemName: "sun.max.fill").font(.system(size: 18)).foregroundStyle(.yellow)
                .frame(width: 40, height: 40).contentShape(Rectangle())
                .offset(x: side / 2 + 20, y: handleY)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if biasBase == nil { biasBase = vm.exposureBias }
                        vm.setExposureBias((biasBase ?? 0) - Float(v.translation.height / 60))
                    }
                    .onEnded { _ in biasBase = nil })
        }
        .position(mark.point)
        .transition(.scale(scale: 1.4).combined(with: .opacity))
        .task(id: mark.id) {
            // Fade away after a while unless locked or being adjusted.
            guard !mark.locked else { return }
            try? await Task.sleep(for: .seconds(3))
            if biasBase == nil, vm.focusMark?.id == mark.id { withAnimation { vm.focusMark = nil } }
        }
    }

    private func statusView(_ status: CameraStatus) -> some View {
        VStack(spacing: 14) {
            Text(status.message).foregroundStyle(.white.opacity(0.8))
            if status.needsSettings {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent).tint(.pink)
            }
        }
    }

    // MARK: - Top bar

    /// Same controls in photo and video mode, each in a fixed-size slot so nothing shifts or stretches.
    private var topBar: some View {
        HStack(spacing: 6) {
            topIcon("gearshape", on: false) { showSettings = true }
                .accessibilityIdentifier("settings")
            if vm.photoMode {
                if CameraManager.isAvailable {
                    topIcon("camera", on: false) { vm.backToCamera() }
                }
                PhotosPicker(selection: $pickerItem, matching: .images) { slot(Image(systemName: "photo")) }
            } else {
                topIcon(flashIcon, on: flashActive, action: vm.cycleFlash)
                    .accessibilityIdentifier("flash")
                topIcon("timer", on: vm.timerSeconds > 0, action: vm.cycleTimer)
                    .overlay(alignment: .bottomTrailing) {
                        if vm.timerSeconds > 0 {
                            Text("\(vm.timerSeconds)").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black).frame(minWidth: 14, minHeight: 14)
                                .background(Circle().fill(Color.yellow)).allowsHitTesting(false)
                        }
                    }
                    .accessibilityIdentifier("timer")
                Button(action: vm.cycleAspect) {
                    slot(Text(vm.aspect.rawValue).font(.system(size: 11, weight: .semibold))
                        .frame(width: 32, height: 20)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white, lineWidth: 1.2)))
                }
                .disabled(vm.recordingSince != nil)
                .opacity(vm.recordingSince != nil ? 0.4 : 1)
                .accessibilityIdentifier("aspect")
                topIcon("hand.tap", on: vm.tapToShoot) { vm.tapToShoot.toggle() }
                    .accessibilityIdentifier("tapToShoot")
                topIcon("grid", on: vm.grid) { vm.grid.toggle() }
                    .accessibilityIdentifier("grid")
            }
            Spacer(minLength: 0)
            slot(Text("对比").font(.system(size: 15, weight: .medium)))
                .onLongPressGesture(minimumDuration: 0, perform: {}, onPressingChanged: { vm.params.bypass = $0 })
            if !vm.photoMode {
                topIcon("arrow.triangle.2.circlepath", on: false) { vm.switchCamera() }
                    .accessibilityIdentifier("flip")
                    .disabled(vm.recordingSince != nil)
                    .opacity(vm.recordingSince != nil ? 0.4 : 1)
            }
        }
        .foregroundStyle(.white)
        .shadow(radius: 3)
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private func slot<V: View>(_ content: V) -> some View {
        content.frame(width: 40, height: 40).contentShape(Rectangle())
    }

    private func topIcon(_ name: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            slot(Image(systemName: name).font(.system(size: 18, weight: .regular)).frame(width: 24, height: 24))
        }
        .foregroundStyle(on ? Color.yellow : .white)
    }

    /// Recording time, on its own row under the top bar so it never squeezes the controls.
    @ViewBuilder private var recordingTime: some View {
        if let since = vm.recordingSince {
            TimelineView(.periodic(from: since, by: 1)) { ctx in
                let t = Int(ctx.date.timeIntervalSince(since))
                HStack(spacing: 6) {
                    Circle().fill(.white).frame(width: 7, height: 7)
                    Text(String(format: "%02d:%02d", t / 60, t % 60))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.red, in: Capsule())
            }
            .padding(.top, 4)
        }
    }

    /// Flash in photo mode, torch in video mode — same bolt icons so the bar looks the same.
    private var flashIcon: String {
        if vm.captureMode == .video { return vm.torchOn ? "bolt.fill" : "bolt.slash.fill" }
        switch vm.flash {
        case .off: return "bolt.slash.fill"
        case .auto: return "bolt.badge.automatic.fill"
        case .on: return "bolt.fill"
        }
    }

    private var flashActive: Bool { vm.captureMode == .video ? vm.torchOn : vm.flash != .off }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if !vm.photoMode && vm.cameraState.zoomButtons.count > 1 && panel == .none { zoomButtons }
            HStack {
                sideButton("美颜", "face.smiling", active: panel == .beauty) { toggle(.beauty) }
                Spacer()
                Button(action: vm.shutter) { shutterIcon }
                    .accessibilityIdentifier("shutter")
                    .overlay(alignment: .trailing) {
                        if vm.recordingSince != nil {
                            // Still photo while recording, like Apple Camera.
                            Button(action: vm.photoWhileRecording) {
                                Circle().fill(.white).frame(width: 38, height: 38)
                                    .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 1))
                                    .scaleEffect(vm.isCapturing ? 0.85 : 1)
                                    .animation(.snappy(duration: 0.15), value: vm.isCapturing)
                            }
                            .offset(x: 58)
                            .accessibilityIdentifier("photoWhileRecording")
                        }
                    }
                Spacer()
                sideButton("滤镜", "camera.filters", active: panel == .filter) { toggle(.filter) }
            }
            .padding(.horizontal, 36)

            ZStack {
                HStack(spacing: 28) {
                    ForEach(BeautyViewModel.CaptureMode.allCases, id: \.self) { mode in
                        Text(LocalizedStringKey(mode.rawValue))
                            .accessibilityIdentifier("mode-\(mode.rawValue)")
                            .accessibilityAddTraits(.isButton)
                            .font(.subheadline.weight(vm.captureMode == mode ? .semibold : .regular))
                            .foregroundStyle(vm.captureMode == mode ? Color.yellow : .white.opacity(0.7))
                            .onTapGesture {
                                if vm.recordingSince == nil && vm.countdown == nil { vm.captureMode = mode }
                            }
                    }
                }
                .opacity(vm.photoMode ? 0 : 1)
                HStack {
                    thumbnail
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea())
    }

    /// Last capture (tap opens Photos); before the first capture it imports a photo to retouch.
    @ViewBuilder private var thumbnail: some View {
        if let thumb = vm.lastThumbnail {
            Button {
                if let url = URL(string: "photos-redirect://") { UIApplication.shared.open(url) }
            } label: {
                Image(uiImage: thumb).resizable().scaledToFill()
                    .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.8), lineWidth: 1))
            }
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle").font(.title3).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }
        }
    }

    private var zoomButtons: some View {
        HStack(spacing: 6) {
            ForEach(vm.cameraState.zoomButtons, id: \.self) { b in
                // The active button shows the live factor, like Apple Camera ("1.4×").
                let next = vm.cameraState.zoomButtons.first(where: { $0 > b }) ?? .infinity
                let active = vm.zoom >= b - 0.01 && vm.zoom < next - 0.01
                Button { vm.setZoom(b, animated: true) } label: {
                    Text(active ? zoomLabel(vm.zoom) + "×" : zoomLabel(b))
                        .font(.caption.weight(.semibold))
                        .frame(width: active ? 38 : 30, height: active ? 38 : 30)
                        .background(Circle().fill(.black.opacity(0.45)))
                        .foregroundStyle(active ? Color.yellow : .white)
                }
            }
        }
        .padding(4)
        .background(Capsule().fill(.black.opacity(0.25)))
    }

    private func zoomLabel(_ z: CGFloat) -> String {
        let r = (z * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : (r < 1 ? String(format: ".%d", Int((r * 10).rounded())) : String(format: "%.1f", r))
    }

    @ViewBuilder private var shutterIcon: some View {
        let video = vm.captureMode == .video && !vm.photoMode
        let recording = vm.recordingSince != nil
        ZStack {
            Circle().strokeBorder(.white, lineWidth: 5).frame(width: 78, height: 78)
            RoundedRectangle(cornerRadius: recording ? 8 : 30)
                .fill(video ? Color.red : Color.white)
                .frame(width: recording ? 30 : 60, height: recording ? 30 : 60)
                .scaleEffect(vm.isCapturing ? 0.9 : 1)
        }
        .animation(.snappy, value: recording)
        .animation(.snappy(duration: 0.15), value: vm.isCapturing)
    }

    private func sideButton(_ title: String, _ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2)
                Text(LocalizedStringKey(title)).font(.caption)
            }
            .foregroundStyle(active ? Color.pink : .white)
            .frame(width: 56)
        }
        .accessibilityIdentifier(title)
    }

    private func toggle(_ p: Panel) { withAnimation(.snappy) { panel = panel == p ? .none : p } }

    // MARK: - Panels

    private var beautyPanel: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(BeautyPreset.all) { preset in
                    let on = preset.matches(vm.params)
                    Text(LocalizedStringKey(preset.name)).font(.subheadline.weight(on ? .semibold : .regular))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(on ? Color.pink.opacity(0.3) : .white.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(on ? Color.pink : .clear, lineWidth: 1.5))
                        .foregroundStyle(on ? Color.pink : .white)
                        .onTapGesture { vm.selectBeautyPreset(preset) }
                }
                if !BeautyPreset.all.contains(where: { $0.matches(vm.params) }) {
                    Text("自定义").font(.subheadline).foregroundStyle(.white.opacity(0.6))
                }
            }
            valueSlider(Binding(get: { vm.params[keyPath: beautyItem.key] },
                                set: { vm.params[keyPath: beautyItem.key] = $0 }))
            HStack(spacing: 0) {
                ForEach(BeautyItem.allCases, id: \.self) { item in
                    let on = item == beautyItem
                    VStack(spacing: 6) {
                        Image(systemName: item.icon).font(.title3)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(on ? Color.pink.opacity(0.25) : .white.opacity(0.12)))
                            .overlay(Circle().strokeBorder(on ? Color.pink : .clear, lineWidth: 2))
                        Text(LocalizedStringKey(item.rawValue)).font(.caption)
                    }
                    .foregroundStyle(on ? Color.pink : .white)
                    .frame(maxWidth: .infinity)
                    .onTapGesture { beautyItem = item }
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal)
        .background(.black.opacity(0.55))
    }

    private var filterPanel: some View {
        VStack(spacing: 14) {
            valueSlider($vm.params.styleIntensity).opacity(vm.params.style == 0 ? 0.3 : 1)
                .disabled(vm.params.style == 0)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StylePreset.all) { style in
                        let on = vm.params.style == style.id
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(style.swatch.gradient)
                                .frame(width: 62, height: 62)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Color.pink : .clear, lineWidth: 2.5))
                                .overlay(alignment: .bottom) {
                                    if style.id == 0 {
                                        Image(systemName: "circle.slash").foregroundStyle(.white).padding(.bottom, 20)
                                    }
                                }
                            Text(LocalizedStringKey(style.name)).font(.caption)
                                .foregroundStyle(on ? Color.pink : .white)
                        }
                        .onTapGesture { vm.selectStyle(style) }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 16)
        .background(.black.opacity(0.55))
    }

    private func valueSlider(_ value: Binding<Float>) -> some View {
        HStack {
            Slider(value: value, in: 0...1).tint(.pink)
            Text("\(Int(value.wrappedValue * 100))").font(.caption.monospacedDigit())
                .foregroundStyle(.white).frame(width: 32)
        }
        .padding(.horizontal, 24)
    }
}

/// Rule-of-thirds grid.
private struct GridOverlay: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                for i in 1...2 {
                    let x = g.size.width * CGFloat(i) / 3, y = g.size.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: g.size.height))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.45), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }
}
