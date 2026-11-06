import SwiftUI

/// The back of a disposable camera: tiny viewfinder, film counter, thumbwheel, flash switch, shutter.
struct CameraBodyView: View {
    @EnvironmentObject private var store: RollStore
    @StateObject private var camera = CameraController()
    @Environment(\.scenePhase) private var scenePhase

    @State private var showLoadFilm = false
    @State private var showLab = false
    @State private var showSettings = false
    @State private var confirmEndEarly = false
    @State private var shutterClosed = false
    @State private var wheelNudge = false

    private var roll: Roll? { store.activeRoll }
    private var needsWind: Bool { (roll.map { !$0.isWound && !$0.isFull }) ?? false }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BodyBackground()
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 16)
                    backPlate(width: geo.size.width)
                    Spacer(minLength: 16)
                    wrapperLabel
                    Spacer(minLength: 16)
                    controlsRow
                    Spacer(minLength: 20)
                    actionArea
                        .frame(height: 120)
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 22)
            }
        }
        .onAppear {
            Haptics.prepare()
            camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                camera.start()
                store.refresh(reschedule: true)
            case .background:
                camera.stop()
            default:
                break
            }
        }
        .sheet(isPresented: $showLoadFilm) { LoadFilmSheet().presentationDetents([.medium]) }
        .sheet(isPresented: $showLab) { LabView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .confirmationDialog("End this roll now?", isPresented: $confirmEndEarly, titleVisibility: .visible) {
            if let roll {
                if roll.frames.isEmpty {
                    Button("Throw away this roll", role: .destructive) { store.sendToLab() }
                } else {
                    Button("Send \(roll.frames.count) shots to the lab", role: .destructive) { store.sendToLab() }
                }
            }
            Button("Keep shooting", role: .cancel) {}
        } message: {
            if let roll {
                Text(roll.frames.isEmpty
                     ? "Nothing has been shot on this roll."
                     : "The \(roll.remaining) unused exposures will be thrown away. Developing still takes the normal time.")
            }
        }
        .alert("Rollcam", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Button { showLab = true } label: {
                Label("Lab", systemImage: "tray.full")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(alignment: .topTrailing) {
                        let count = store.labRolls.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.bold())
                                .padding(5)
                                .background(Circle().fill(Color.orange))
                                .foregroundStyle(.black)
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            Spacer()
            if roll != nil {
                Menu {
                    Button(role: .destructive) { confirmEndEarly = true } label: {
                        Label("Develop early…", systemImage: "forward.end")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
                .padding(.trailing, 8)
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.title3)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.top, 8)
    }

    /// Moulded plastic plate holding the viewfinder, counter and wheel.
    private func backPlate(width: CGFloat) -> some View {
        let finderWidth = width * 0.28
        return HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 8) {
                viewfinder(width: finderWidth)
                Text("VIEWFINDER")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            VStack(spacing: 8) {
                FilmCounter(roll: roll)
                Text("EXP.")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.35))
            }
            ThumbWheel(needsWind: needsWind) { store.markWound() }
                .frame(width: 44, height: 150)
                .offset(x: wheelNudge ? -6 : 0)
                .animation(.interpolatingSpring(stiffness: 600, damping: 8), value: wheelNudge)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func viewfinder(width: CGFloat) -> some View {
        let height = width * 2 / 3
        return ZStack {
            switch camera.access {
            case .denied:
                Color.black
                Image(systemName: "eye.slash").foregroundStyle(.white.opacity(0.5))
            default:
                CameraPreview(session: camera.session)
            }
            // Bright-line frame like a cheap optical finder.
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.white.opacity(0.35), lineWidth: 0.75)
                .padding(width * 0.08)
            LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .center)
            Color.black.opacity(shutterClosed ? 1 : 0)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.28), lineWidth: 1.5))
        .accessibilityLabel("Viewfinder")
    }

    private var wrapperLabel: some View {
        HStack(spacing: 10) {
            Text("ROLLCAM")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.black)
            Text(roll.map { "\($0.capacity) EXP" } ?? "NO FILM")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(.black.opacity(0.75))
            Spacer()
            Text(needsWind ? "WIND ▲▼" : (roll?.isFull == true ? "ROLL FULL" : "ISO 400"))
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(needsWind ? Color(red: 0.75, green: 0.15, blue: 0.05) : .black.opacity(0.75))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.77, blue: 0.16), Color(red: 0.93, green: 0.62, blue: 0.1)],
                                     startPoint: .leading, endPoint: .trailing))
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(red: 0.88, green: 0.32, blue: 0.1)).frame(height: 5)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 14) {
            Button {
                camera.flashOn.toggle()
                Haptics.click()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(camera.flashOn ? Color(red: 1, green: 0.35, blue: 0.2) : Color(white: 0.25))
                        .frame(width: 10, height: 10)
                        .shadow(color: camera.flashOn ? .red : .clear, radius: 6)
                    Image(systemName: camera.flashOn ? "bolt.fill" : "bolt.slash")
                    Text(camera.flashOn ? "FLASH ON" : "FLASH OFF")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .disabled(!camera.torchAvailable)
            .opacity(camera.torchAvailable ? 1 : 0.4)

            Spacer()

            Button {
                camera.flip()
                Haptics.click()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title3)
                    .padding(12)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .accessibilityLabel(camera.position == .front ? "Switch to back camera" : "Switch to front camera")
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    @ViewBuilder
    private var actionArea: some View {
        if let roll {
            if roll.isFull {
                Button {
                    store.sendToLab()
                    Haptics.success()
                    showLab = true
                } label: {
                    Label("Send to lab", systemImage: "shippingbox")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.orange))
                        .foregroundStyle(.black)
                }
            } else {
                ShutterButton(armed: roll.isWound && !camera.isCapturing, action: fire)
            }
        } else {
            Button { showLoadFilm = true } label: {
                Label("Load film", systemImage: "film")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.98, green: 0.77, blue: 0.16)))
                    .foregroundStyle(.black)
            }
        }
    }

    private func fire() {
        guard let roll, !roll.isFull else { return }
        guard roll.isWound else {
            Haptics.warn()
            wheelNudge.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { wheelNudge.toggle() }
            return
        }
        guard camera.access == .authorized else {
            store.lastError = "Rollcam needs camera access. Turn it on in Settings › Rollcam."
            return
        }
        Haptics.shutter()
        withAnimation(.linear(duration: 0.04)) { shutterClosed = true }
        camera.capture(flash: camera.flashOn) { data in
            withAnimation(.easeOut(duration: 0.25)) { shutterClosed = false }
            if let data {
                store.expose(data)
            } else {
                store.lastError = "The shutter jammed. Try again."
            }
        }
    }
}

// MARK: - Parts

private struct BodyBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.075, blue: 0.07)
            Canvas { context, size in
                // Subtle moulded-plastic speckle.
                var rng = SeededGenerator(seed: 7)
                for _ in 0..<900 {
                    let x = CGFloat(rng.nextDouble()) * size.width
                    let y = CGFloat(rng.nextDouble()) * size.height
                    let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.035)))
                }
            }
            LinearGradient(colors: [.white.opacity(0.04), .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

private struct FilmCounter: View {
    let roll: Roll?

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            Circle().stroke(Color(white: 0.3), lineWidth: 2)
            Text(label)
                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.12))
                .shadow(color: .orange.opacity(0.6), radius: 4)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: label)
        }
        .frame(width: 64, height: 64)
        .accessibilityLabel(roll.map { "\($0.remaining) exposures left" } ?? "No film loaded")
    }

    private var label: String {
        guard let roll else { return "–" }
        return String(roll.remaining)
    }
}

private struct ShutterButton: View {
    let armed: Bool
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.05))
                    .frame(width: 104, height: 104)
                Circle()
                    .fill(LinearGradient(colors: armed
                                         ? [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.86, green: 0.35, blue: 0.08)]
                                         : [Color(white: 0.35), Color(white: 0.22)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 3)
            }
        }
        .buttonStyle(PressedScaleStyle())
        .accessibilityLabel(armed ? "Shutter" : "Shutter — wind the film first")
    }
}

private struct PressedScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
