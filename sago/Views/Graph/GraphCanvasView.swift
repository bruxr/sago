//
//  GraphCanvasView.swift
//  sago
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Colors used to draw nodes, keyed by their first label.
enum GraphPalette {
    static func color(for label: String) -> Color {
        switch label {
        case "Movie": return .orange
        case "Person": return .blue
        default:
            let colors: [Color] = [.green, .purple, .pink, .teal, .indigo, .mint]
            let hash = label.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
            return colors[hash % colors.count]
        }
    }
}

/// Maps world coordinates to screen coordinates: `screen = world * scale + translation`.
final class GraphCamera {
    var scale: CGFloat = 1
    var translation: CGPoint = .zero
    /// When true the camera keeps the whole graph in view.
    var isAutoFitting = true
    var isConverged = false
    var hoverLocation: CGPoint?

    private var lastDate: Date?
    private var hasPlacedInitially = false

    static let scaleRange: ClosedRange<CGFloat> = 0.1...6

    func toWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - translation.x) / scale, y: (point.y - translation.y) / scale)
    }

    /// Zooms by `factor`, keeping the world point under `anchor` fixed on screen.
    func zoom(by factor: CGFloat, anchor: CGPoint) {
        let world = toWorld(anchor)
        scale = min(max(scale * factor, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        translation = CGPoint(x: anchor.x - world.x * scale, y: anchor.y - world.y * scale)
        isAutoFitting = false
    }

    func pan(by delta: CGSize) {
        translation.x += delta.width
        translation.y += delta.height
        isAutoFitting = false
    }

    /// Eases the camera toward a framing of `bounds` inside `visibleRect`.
    func update(to date: Date, fitting bounds: CGRect, in visibleRect: CGRect) {
        defer { lastDate = date }
        guard isAutoFitting, visibleRect.width > 0, visibleRect.height > 0 else {
            isConverged = true
            return
        }

        let padding: CGFloat = 60
        let width = max(bounds.width + padding * 2, 1)
        let height = max(bounds.height + padding * 2, 1)
        // Never zoom in past 1.5× just to fill the space.
        let targetScale = min(min(visibleRect.width / width, visibleRect.height / height), 1.5)
        let targetTranslation = CGPoint(
            x: visibleRect.midX - bounds.midX * targetScale,
            y: visibleRect.midY - bounds.midY * targetScale
        )

        guard hasPlacedInitially, let lastDate else {
            scale = targetScale
            translation = targetTranslation
            hasPlacedInitially = true
            isConverged = false
            return
        }

        // Exponential smoothing gives a soft, spring-like follow.
        let dt = min(date.timeIntervalSince(lastDate), 0.1)
        let t = 1 - exp(-dt * 7)
        scale += (targetScale - scale) * t
        translation.x += (targetTranslation.x - translation.x) * t
        translation.y += (targetTranslation.y - translation.y) * t

        isConverged = abs(targetScale - scale) < 0.001
            && hypot(targetTranslation.x - translation.x, targetTranslation.y - translation.y) < 0.5
    }

    func resetClock() {
        lastDate = nil
        isConverged = false
    }
}

/// Center pane: draws the graph with a force-directed layout and supports zoom, pan and selection.
struct GraphCanvasView: View {
    let nodes: [GraphNode]
    let relationships: [GraphRelationship]
    /// Space covered by floating panels; auto-fit keeps the graph inside the remaining area.
    let obscuredInsets: EdgeInsets
    @Binding var selection: GraphSelection?

    @State private var simulation: ForceSimulation
    @State private var camera = GraphCamera()
    @State private var labelSizes = LabelSizeCache()
    @State private var isAnimating = true
    @State private var selectionDate = Date.distantPast
    @State private var lastDragTranslation: CGSize?
    @State private var lastMagnification: CGFloat?
    #if os(macOS)
    @State private var scrollMonitor: Any?
    #endif

    private let nodeRadius: CGFloat = 26

    init(nodes: [GraphNode], relationships: [GraphRelationship], obscuredInsets: EdgeInsets, selection: Binding<GraphSelection?>) {
        self.nodes = nodes
        self.relationships = relationships
        self.obscuredInsets = obscuredInsets
        self._selection = selection
        self._simulation = State(initialValue: ForceSimulation(nodes: nodes, relationships: relationships))
    }

    var body: some View {
        GeometryReader { proxy in
            let safeArea = proxy.safeAreaInsets
            TimelineView(.animation(paused: !isAnimating)) { timeline in
                Canvas { context, size in
                    let visibleRect = visibleRect(in: size, safeArea: safeArea)
                    simulation.advance(to: timeline.date)
                    camera.update(to: timeline.date, fitting: simulation.boundingBox, in: visibleRect)
                    draw(in: &context, date: timeline.date)
                    stopAnimatingIfIdle(at: timeline.date)
                }
            }
            .ignoresSafeArea()
            .background(Color.graphBackground.ignoresSafeArea())
            .contentShape(.rect)
            .gesture(panGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(tapGesture)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    camera.hoverLocation = location
                case .ended:
                    camera.hoverLocation = nil
                }
            }
            .overlay(alignment: .bottomTrailing) {
                fitButton
                    .padding(.trailing, obscuredInsets.trailing + 12)
                    .padding(.bottom, 12)
            }
        }
        .onChange(of: obscuredInsets) { wake() }
        .onChange(of: selection) {
            selectionDate = .now
            wake()
        }
        #if os(macOS)
        .onAppear(perform: installScrollMonitor)
        .onDisappear(perform: removeScrollMonitor)
        #endif
    }

    // MARK: - Layout helpers

    /// The part of the canvas not covered by the toolbar or floating panels.
    private func visibleRect(in size: CGSize, safeArea: EdgeInsets) -> CGRect {
        let top = safeArea.top + obscuredInsets.top
        let leading = max(safeArea.leading, obscuredInsets.leading)
        let trailing = max(safeArea.trailing, obscuredInsets.trailing)
        let bottom = max(safeArea.bottom, obscuredInsets.bottom)
        return CGRect(
            x: leading,
            y: top,
            width: max(size.width - leading - trailing, 1),
            height: max(size.height - top - bottom, 1)
        )
    }

    private func wake() {
        camera.resetClock()
        isAnimating = true
    }

    private func stopAnimatingIfIdle(at date: Date) {
        let pulseFinished = date.timeIntervalSince(selectionDate) > 1
        guard simulation.isSettled, camera.isConverged, pulseFinished, isAnimating else { return }
        // Defer the state change; mutating state while rendering is not allowed.
        Task { @MainActor in isAnimating = false }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, date: Date) {
        let positions = simulation.positions
        context.translateBy(x: camera.translation.x, y: camera.translation.y)
        context.scaleBy(x: camera.scale, y: camera.scale)

        // Relationships.
        for relationship in relationships {
            guard let start = positions[relationship.startNodeID],
                  let end = positions[relationship.endNodeID] else { continue }
            drawRelationship(relationship, from: start, to: end, in: &context)
        }

        // Nodes.
        for node in nodes {
            guard let position = positions[node.id] else { continue }
            let isSelected = selection == .node(node.id)
            let radius = nodeRadius * (isSelected ? 1.15 * pulse(at: date) : 1)
            let rect = CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
            let color = GraphPalette.color(for: node.labels.first ?? "")

            if isSelected {
                let halo = rect.insetBy(dx: -6, dy: -6)
                context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.25)))
            }
            context.fill(Path(ellipseIn: rect), with: .color(color))
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(isSelected ? .primary : color.mix(with: .black, by: 0.25)),
                lineWidth: isSelected ? 2.5 : 1.5
            )

            let caption = context.resolve(
                Text(node.caption)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
            )
            // Clip the caption to the node so long names don't spill out.
            context.drawLayer { layer in
                layer.clip(to: Path(ellipseIn: rect.insetBy(dx: 3, dy: 3)))
                layer.draw(caption, at: position, anchor: .center)
            }
        }
    }

    private func drawRelationship(_ relationship: GraphRelationship, from start: CGPoint, to end: CGPoint, in context: inout GraphicsContext) {
        guard let edge = EdgeGeometry(from: start, to: end, nodeRadius: nodeRadius) else { return }
        let isSelected = selection == .relationship(relationship.id)
        let lineColor: Color = isSelected ? .accentColor : .secondary.opacity(0.7)

        var line = Path()
        line.move(to: edge.from)
        line.addLine(to: edge.tip)
        context.stroke(line, with: .color(lineColor), lineWidth: isSelected ? 2.5 : 1.2)

        // Arrow head.
        let arrowLength: CGFloat = isSelected ? 10 : 8, arrowWidth: CGFloat = isSelected ? 5 : 4
        let base = CGPoint(x: edge.tip.x - edge.ux * arrowLength, y: edge.tip.y - edge.uy * arrowLength)
        var arrow = Path()
        arrow.move(to: edge.tip)
        arrow.addLine(to: CGPoint(x: base.x - edge.uy * arrowWidth, y: base.y + edge.ux * arrowWidth))
        arrow.addLine(to: CGPoint(x: base.x + edge.uy * arrowWidth, y: base.y - edge.ux * arrowWidth))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(isSelected ? .accentColor : .secondary))

        // Type label along the line, kept upright.
        var labelContext = context
        labelContext.translateBy(x: edge.mid.x, y: edge.mid.y)
        labelContext.rotate(by: .radians(edge.labelAngle))
        let label = labelContext.resolve(
            Text(relationship.type)
                .font(.system(size: 7, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        )
        // Remember the label size so taps on it can be hit-tested.
        labelSizes.sizes[relationship.id] = label.measure(in: CGSize(width: 400, height: 40))
        labelContext.draw(label, at: EdgeGeometry.labelCenter, anchor: .center)
    }

    /// A damped oscillation that makes a newly selected node "bounce".
    private func pulse(at date: Date) -> CGFloat {
        let t = date.timeIntervalSince(selectionDate)
        guard t >= 0, t < 1 else { return 1 }
        return 1 + 0.25 * exp(-5 * t) * sin(18 * t)
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let previous = lastDragTranslation ?? .zero
                camera.pan(by: CGSize(
                    width: value.translation.width - previous.width,
                    height: value.translation.height - previous.height
                ))
                lastDragTranslation = value.translation
                wake()
            }
            .onEnded { _ in lastDragTranslation = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let previous = lastMagnification ?? 1
                camera.zoom(by: value.magnification / previous, anchor: value.startLocation)
                lastMagnification = value.magnification
                wake()
            }
            .onEnded { _ in lastMagnification = nil }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let hit = hitTest(value.location)
                withAnimation(.snappy) {
                    selection = hit
                }
            }
    }

    /// Finds the node or relationship under a point in canvas coordinates.
    /// Nodes (including their name text) win over relationships.
    private func hitTest(_ point: CGPoint) -> GraphSelection? {
        let world = camera.toWorld(point)
        let positions = simulation.positions
        // Keep targets at least ~14pt on screen even when zoomed far out.
        let minimumTarget = 14 / camera.scale

        let node = nodes.last { node in
            guard let position = positions[node.id] else { return false }
            return hypot(position.x - world.x, position.y - world.y) <= max(nodeRadius, minimumTarget)
        }
        if let node {
            return .node(node.id)
        }

        let slop = max(3, 6 / camera.scale)
        let relationship = relationships.last { relationship in
            guard let start = positions[relationship.startNodeID],
                  let end = positions[relationship.endNodeID],
                  let edge = EdgeGeometry(from: start, to: end, nodeRadius: nodeRadius) else { return false }

            // Convert into the label's rotated coordinate space.
            let local = edge.toLabelSpace(world)
            let size = labelSizes.sizes[relationship.id] ?? CGSize(width: 40, height: 9)
            let labelRect = CGRect(
                x: EdgeGeometry.labelCenter.x - size.width / 2,
                y: EdgeGeometry.labelCenter.y - size.height / 2,
                width: size.width,
                height: size.height
            ).insetBy(dx: -slop, dy: -slop)
            if labelRect.contains(local) { return true }

            // Also accept taps on the line itself.
            let halfLength = hypot(edge.tip.x - edge.from.x, edge.tip.y - edge.from.y) / 2
            return abs(local.x) <= halfLength && abs(local.y) <= slop
        }
        return relationship.map { .relationship($0.id) }
    }

    // MARK: - Fit button

    private var fitButton: some View {
        Button {
            camera.isAutoFitting = true
            wake()
        } label: {
            Label("Fit Graph", systemImage: "arrow.down.right.and.arrow.up.left")
                .labelStyle(.iconOnly)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help("Fit Graph")
    }

    // MARK: - Scroll wheel zoom (macOS)

    #if os(macOS)
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        let camera = camera
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Only handle scrolling while the pointer is over the canvas (not a panel).
            guard let anchor = camera.hoverLocation else { return event }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
            camera.zoom(by: exp(delta * 0.01), anchor: anchor)
            isAnimating = true
            camera.resetClock()
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
    }
    #endif
}

/// Line geometry for a relationship, trimmed to the edges of its nodes.
private struct EdgeGeometry {
    let from: CGPoint
    let tip: CGPoint
    let mid: CGPoint
    let ux: CGFloat
    let uy: CGFloat
    /// Angle of the type label, flipped so text is never upside down.
    let labelAngle: CGFloat

    /// Label position relative to `mid` in the rotated label space (slightly above the line).
    static let labelCenter = CGPoint(x: 0, y: -5)

    init?(from start: CGPoint, to end: CGPoint, nodeRadius: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > nodeRadius * 2 else { return nil }
        ux = dx / length
        uy = dy / length
        from = CGPoint(x: start.x + ux * nodeRadius, y: start.y + uy * nodeRadius)
        tip = CGPoint(x: end.x - ux * nodeRadius, y: end.y - uy * nodeRadius)
        mid = CGPoint(x: (from.x + tip.x) / 2, y: (from.y + tip.y) / 2)
        var angle = atan2(dy, dx)
        if angle > .pi / 2 || angle < -.pi / 2 { angle += .pi }
        labelAngle = angle
    }

    /// Converts a world point into the label's translated + rotated coordinate space.
    func toLabelSpace(_ point: CGPoint) -> CGPoint {
        let vx = point.x - mid.x
        let vy = point.y - mid.y
        let c = cos(labelAngle), s = sin(labelAngle)
        return CGPoint(x: vx * c + vy * s, y: -vx * s + vy * c)
    }
}

/// Measured relationship label sizes from the last render, used for hit testing.
private final class LabelSizeCache {
    var sizes: [Int: CGSize] = [:]
}

private extension Color {
    static var graphBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

#Preview {
    GraphCanvasView(
        nodes: PlaceholderData.nodes,
        relationships: PlaceholderData.relationships,
        obscuredInsets: EdgeInsets(),
        selection: .constant(.node(4))
    )
    .frame(width: 800, height: 600)
}
