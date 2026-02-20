import SwiftUI
import Cocoa

// MARK: - Design Tokens

private enum OC {
    static let teal = Color(red: 0.08, green: 0.72, blue: 0.65)
    static let tealDim = Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.5)
    static let red = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let green = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let notchBlack = Color.black
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textMuted = Color.white.opacity(0.4)
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var state: MiloState = .idle
    @Published var transcript: String = ""
    @Published var audioLevel: Float = 0
}

// MARK: - The Dynamic Island HUD

struct RecordingHUD: View {
    @ObservedObject var model: HUDModel
    
    @State private var glowPulse = false
    @State private var hasAppeared = false
    
    // Geometry for the notch expansion
    private let notchWidth: CGFloat = 190
    private let notchHeight: CGFloat = 34
    
    private var state: MiloState { model.state }
    private var transcript: String { model.transcript }
    private var audioLevel: Float { model.audioLevel }
    private var isExpanded: Bool { state != .idle }
    private var stateKey: String { state.description }
    private var expandedWidth: CGFloat {
        switch state {
        case .recording: return 560
        case .processing: return 540
        case .speaking: return 640
        case .idle: return notchWidth
        }
    }
    
    private var accentColor: Color {
        switch state {
        case .idle:
            return Color.white.opacity(0.25)
        case .recording:
            return OC.red
        case .processing:
            return OC.teal
        case .speaking:
            return OC.green
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                DynamicBackdrop(
                    accentColor: accentColor,
                    isExpanded: isExpanded,
                    glowPulse: glowPulse
                )
                
                islandContent
                    .id(stateKey)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                        removal: .opacity
                    ))
            }
                .frame(width: isExpanded ? expandedWidth : notchWidth)
                .frame(minHeight: notchHeight)
                .fixedSize(horizontal: false, vertical: true)
                .clipShape(DynamicIslandShape(cornerRadius: isExpanded ? 22 : 17))
                .shadow(color: .black.opacity(isExpanded ? 0.42 : 0), radius: 18, y: 8)
                .scaleEffect(hasAppeared ? 1.0 : 0.985, anchor: .top)
                .offset(y: hasAppeared ? 0 : -3)
                .opacity(hasAppeared ? 1.0 : 0.01)
        }
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.74)) {
                hasAppeared = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
        .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.86, blendDuration: 0.2), value: isExpanded)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.9, blendDuration: 0.12), value: stateKey)
    }
    
    @ViewBuilder
    private var islandContent: some View {
        switch state {
        case .idle:
            // Compact: just the notch shape, nothing visible
            Color.clear
                .frame(height: notchHeight)
            
        case .recording:
            VStack(spacing: 10) {
                // Top row: recording indicator
                HStack {
                    // Pulsing red dot
                    Circle()
                        .fill(OC.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: OC.red.opacity(0.6), radius: 4)
                        .modifier(PulseModifier())
                    
                    Text("Listening")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(OC.textSecondary)
                    
                    Spacer()
                    
                    // Mini level indicator
                    MiniLevelDots(level: audioLevel)
                }
                .padding(.top, 12)
                .padding(.horizontal, 20)
                
                // Audio visualizer
                AudioVisualizerView(level: audioLevel)
                    .frame(height: 40)
                    .padding(.horizontal, 16)
                
                // Transcript (if available)
                if !transcript.isEmpty {
                    Text(transcript)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(OC.textPrimary.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.bottom, 16)
            
        case .processing:
            VStack(spacing: 10) {
                HStack {
                    ProcessingOrb()
                        .frame(width: 16, height: 16)
                    
                    Text("Thinking")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(OC.textSecondary)
                    
                    Spacer()
                    
                    BouncingDots()
                }
                .padding(.top, 12)
                .padding(.horizontal, 20)
                
                if !transcript.isEmpty {
                    Text(transcript)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(OC.textMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 16)
            
        case .speaking(let response):
            VStack(spacing: 10) {
                HStack {
                    SpeakingWave()
                        .frame(width: 20, height: 14)
                    
                    Text("Milo")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(OC.teal)
                    
                    Spacer()
                    
                    Text("hotkey to stop")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(OC.textMuted)
                }
                .padding(.top, 12)
                .padding(.horizontal, 20)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Now speaking")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(OC.textMuted)
                        .textCase(.uppercase)
                    
                    Text(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "..." : response)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(OC.textPrimary.opacity(0.96))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Dynamic Island Shape

struct DynamicIslandShape: Shape {
    var cornerRadius: CGFloat
    
    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        return RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect)
    }
}

// MARK: - Layered Backdrop

private struct DynamicBackdrop: View {
    let accentColor: Color
    let isExpanded: Bool
    let glowPulse: Bool
    
    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            
            ZStack {
                OC.notchBlack
                
                // Subtle neutral sheen to avoid a flat rectangle while matching notch black.
                RadialGradient(
                    colors: [
                        Color.white.opacity(isExpanded ? (glowPulse ? 0.05 : 0.035) : 0.015),
                        .clear
                    ],
                    center: .top,
                    startRadius: 2,
                    endRadius: max(width, height) * 0.7
                )
                
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Thin accent thread instead of whole-surface tint.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                accentColor.opacity(isExpanded ? (glowPulse ? 0.20 : 0.12) : 0.06),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 0.38, height: 1)
                    .offset(y: isExpanded ? 9 : 11)
            }
        }
    }
}

// MARK: - Audio Visualizer

struct AudioVisualizerView: View {
    let level: Float
    
    @State private var phase: Double = 0
    @State private var bars: [CGFloat] = Array(repeating: 0.03, count: 36)
    
    private let timer = Timer.publish(every: 0.035, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<bars.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barGradient(height: bars[i]))
                    .frame(width: 2.5, height: max(bars[i] * 40, 1.5))
            }
        }
        .onReceive(timer) { _ in
            updateBars()
        }
    }
    
    private func updateBars() {
        phase += 0.12
        let base = CGFloat(min(max(level * 4.0, 0.02), 1.0))
        let count = Double(bars.count)
        let center = count / 2.0
        
        withAnimation(.easeOut(duration: 0.05)) {
            for i in 0..<bars.count {
                let distFromCenter = abs(Double(i) - center) / center
                // Smooth bell curve envelope
                let envelope = exp(-distFromCenter * distFromCenter * 2.0)
                let wave = sin(Double(i) * 0.45 + phase) * 0.3 + 0.7
                let noise = Double.random(in: 0.9...1.1)
                let target = base * CGFloat(envelope * wave * noise)
                
                let current = bars[i]
                if target > current {
                    bars[i] = current + (target - current) * 0.65
                } else {
                    bars[i] = current + (target - current) * 0.2
                }
            }
        }
    }
    
    private func barGradient(height: CGFloat) -> LinearGradient {
        LinearGradient(
            colors: [
                OC.teal.opacity(0.4 + Double(height) * 0.6),
                OC.teal
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

// MARK: - Mini Level Dots (top-right indicator)

struct MiniLevelDots: View {
    let level: Float
    private let dotCount = 5
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<dotCount, id: \.self) { i in
                let threshold = Float(i) / Float(dotCount)
                Circle()
                    .fill(level > threshold ? OC.teal : OC.teal.opacity(0.15))
                    .frame(width: 4, height: 4)
            }
        }
    }
}

// MARK: - Processing Orb

struct ProcessingOrb: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: [OC.teal, OC.teal.opacity(0.2), OC.teal],
                    center: .center
                )
            )
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

// MARK: - Bouncing Dots

struct BouncingDots: View {
    @State private var active: Int = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(OC.teal)
                    .frame(width: 4, height: 4)
                    .scaleEffect(active == i ? 1.4 : 0.8)
                    .opacity(active == i ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.3), value: active)
            }
        }
        .onReceive(timer) { _ in
            active = (active + 1) % 3
        }
    }
}

// MARK: - Speaking Wave

struct SpeakingWave: View {
    @State private var phase: Double = 0
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()
    @State private var heights: [CGFloat] = [0.3, 0.6, 0.9, 0.6, 0.3]
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(OC.teal)
                    .frame(width: 2, height: heights[i] * 14)
            }
        }
        .onReceive(timer) { _ in
            phase += 0.5
            withAnimation(.easeInOut(duration: 0.12)) {
                for i in 0..<5 {
                    heights[i] = CGFloat(sin(Double(i) * 1.2 + phase) * 0.35 + 0.55)
                }
            }
        }
    }
}

// MARK: - Pulse Modifier

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - HUD Window

class HUDWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar + 1  // Above menu bar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        
        positionAtNotch()
    }
    
    func positionAtNotch() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let windowWidth = self.frame.width
        // Center horizontally, flush with top of screen
        let x = screenFrame.midX - windowWidth / 2
        let y = screenFrame.maxY - self.frame.height
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
