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
    private var needsIntro = true
    private var introStart: Date?

    static let scaleRange: ClosedRange<CGFloat> = 0.1...6
    /// Critically damped (no bounce): moves quickly at first, then settles smoothly.
    private static let introSpring = Spring(duration: 0.75, bounce: 0)
    private static let introStartScale: CGFloat = 1.2
    private static let introFadeDuration: TimeInterval = 0.2

    var isPlayingIntro: Bool { needsIntro || introStart != nil }

    /// Frames a newly loaded graph immediately and replays the intro zoom.
    func showNewGraph() {
        isAutoFitting = true
        hasPlacedInitially = false
        needsIntro = true
        introStart = nil
        resetClock()
    }

    /// Extra scale (1.2 → 1) and opacity (0 → 1) applied while a new graph appears.
    func intro(at date: Date) -> (scale: CGFloat, opacity: Double) {
        if needsIntro {
            introStart = date
            needsIntro = false
        }
        guard let introStart else { return (1, 1) }
        let time = date.timeIntervalSince(introStart)
        let scale = Self.introSpring.value(
            fromValue: Double(Self.introStartScale),
            toValue: 1,
            initialVelocity: 0,
            time: time
        )
        let opacity = min(time / Self.introFadeDuration, 1)
        // The spring approaches 1 asymptotically; stop once the difference is invisible.
        if abs(scale - 1) < 0.0005 {
            self.introStart = nil
            return (1, 1)
        }
        return (CGFloat(scale), opacity)
    }

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

        guard hasPlacedInitially else {
            scale = targetScale
            translation = targetTranslation
            hasPlacedInitially = true
            isConverged = false
            return
        }

        // Exponential smoothing gives a soft, spring-like follow.
        // Right after waking there's no previous frame, so hold still for one frame instead of snapping.
        let dt = lastDate.map { min(date.timeIntervalSince($0), 0.1) } ?? 0
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

    @State private var simulation = ForceSimulation()
    @State private var isLayingOut = false
    @State private var camera = GraphCamera()
    @State private var labelSizes = LabelSizeCache()
    @State private var isAnimating = true
    @State private var lastDragTranslation: CGSize?
    @State private var dragMode: DragMode?
    @State private var lastMagnification: CGFloat?
    /// The canvas's frame in global space. Pointer locations are converted with its origin so they
    /// line up with what's drawn, even though the canvas extends under the toolbar.
    @State private var canvasFrame: CGRect = .zero
    #if os(macOS)
    @State private var scrollMonitor: Any?
    #endif

    private let nodeRadius: CGFloat = 26

    init(nodes: [GraphNode], relationships: [GraphRelationship], obscuredInsets: EdgeInsets, selection: Binding<GraphSelection?>) {
        self.nodes = nodes
        self.relationships = relationships
        self.obscuredInsets = obscuredInsets
        self._selection = selection
    }

    var body: some View {
        GeometryReader { proxy in
            let safeArea = proxy.safeAreaInsets
            TimelineView(.animation(paused: !isAnimating)) { timeline in
                Canvas { context, size in
                    let visibleRect = visibleRect(in: size, safeArea: safeArea)
                    simulation.advance(to: timeline.date)
                    camera.update(to: timeline.date, fitting: simulation.boundingBox, in: visibleRect)
                    let intro = camera.intro(at: timeline.date)
                    // Fade in and scale around the center of the visible area while a new graph appears.
                    context.opacity = intro.opacity
                    context.translateBy(x: visibleRect.midX, y: visibleRect.midY)
                    context.scaleBy(x: intro.scale, y: intro.scale)
                    context.translateBy(x: -visibleRect.midX, y: -visibleRect.midY)
                    draw(in: &context)
                    stopAnimatingIfIdle()
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { canvasFrame = $0 }
            }
            .ignoresSafeArea()
            .background(Color.graphBackground.ignoresSafeArea())
            .contentShape(.rect)
            .gesture(panGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(tapGesture)
            .onContinuousHover(coordinateSpace: .global) { phase in
                switch phase {
                case .active(let location):
                    camera.hoverLocation = canvasPoint(fromGlobal: location)
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
        .overlay {
            if isLayingOut {
                ProgressView("Laying out graph…")
                    .padding(obscuredInsets)
            }
        }
        // Only a new set of nodes needs a fresh layout; label edits just redraw.
        // A newer graph cancels a layout still in progress.
        .task(id: LayoutInput(nodeIDs: nodes.map(\.id), relationships: relationships)) { await reload() }
        .onChange(of: obscuredInsets) { wake() }
        .onChange(of: selection) { wake() }
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

    /// Lays out a new set of nodes and relationships and plays the intro animation.
    private func reload() async {
        isLayingOut = true
        await simulation.load(nodes: nodes, relationships: relationships)
        guard !Task.isCancelled else { return }
        isLayingOut = false
        labelSizes.sizes = [:]
        camera.showNewGraph()
        isAnimating = true
    }

    private func stopAnimatingIfIdle() {
        guard simulation.isSettled, camera.isConverged, !camera.isPlayingIntro, isAnimating else { return }
        // Defer the state change; mutating state while rendering is not allowed.
        Task { @MainActor in isAnimating = false }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext) {
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
            let rect = CGRect(x: position.x - nodeRadius, y: position.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)
            let color = GraphPalette.color(for: node.labels.first ?? "")

            context.fill(Path(ellipseIn: rect), with: .color(color))
            // Selected nodes get the same accent highlight as selected relationships.
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(isSelected ? .accentColor : color.mix(with: .black, by: 0.25)),
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

    // MARK: - Gestures

    private enum DragMode {
        case pan
        /// Dragging a node; `offset` keeps the point that was grabbed under the pointer.
        case node(id: Int, offset: CGVector)
    }

    /// Drags a node when the drag starts on one, otherwise pans the camera.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if dragMode == nil {
                    let start = camera.toWorld(canvasPoint(fromGlobal: value.startLocation))
                    if let id = nodeID(atWorld: start), let position = simulation.positions[id] {
                        dragMode = .node(id: id, offset: CGVector(dx: position.x - start.x, dy: position.y - start.y))
                        // The user is arranging the graph; stop re-framing it automatically.
                        camera.isAutoFitting = false
                    } else {
                        dragMode = .pan
                    }
                }

                switch dragMode {
                case .node(let id, let offset):
                    let world = camera.toWorld(canvasPoint(fromGlobal: value.location))
                    let target = CGPoint(x: world.x + offset.dx, y: world.y + offset.dy)
                    simulation.move(id, to: clampedToWindow(target))
                case .pan, nil:
                    let previous = lastDragTranslation ?? .zero
                    camera.pan(by: CGSize(
                        width: value.translation.width - previous.width,
                        height: value.translation.height - previous.height
                    ))
                    lastDragTranslation = value.translation
                }
                wake()
            }
            .onEnded { _ in
                dragMode = nil
                lastDragTranslation = nil
                wake()
            }
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
        SpatialTapGesture(coordinateSpace: .global)
            .onEnded { value in
                let hit = hitTest(canvasPoint(fromGlobal: value.location))
                withAnimation(.snappy) {
                    selection = hit
                }
            }
    }

    private func canvasPoint(fromGlobal point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - canvasFrame.minX, y: point.y - canvasFrame.minY)
    }

    /// Clamps a world point so a node centered there stays fully inside the window.
    private func clampedToWindow(_ world: CGPoint) -> CGPoint {
        let radius = nodeRadius * camera.scale
        let screen = CGPoint(x: world.x * camera.scale + camera.translation.x, y: world.y * camera.scale + camera.translation.y)
        let clamped = CGPoint(
            x: min(max(screen.x, radius), max(canvasFrame.width - radius, radius)),
            y: min(max(screen.y, radius), max(canvasFrame.height - radius, radius))
        )
        return camera.toWorld(clamped)
    }

    /// Finds the node or relationship under a point in canvas coordinates.
    /// Nodes win over relationships; among candidates the closest one wins.
    private func hitTest(_ point: CGPoint) -> GraphSelection? {
        let world = camera.toWorld(point)
        let positions = simulation.positions
        if let id = nodeID(atWorld: world) {
            return .node(id)
        }

        let slop = max(3, 6 / camera.scale)
        let relationshipHit = relationships
            .compactMap { relationship -> (id: Int, distance: CGFloat)? in
                guard let start = positions[relationship.startNodeID],
                      let end = positions[relationship.endNodeID],
                      let edge = EdgeGeometry(from: start, to: end, nodeRadius: nodeRadius) else { return nil }

                // Convert into the label's rotated coordinate space.
                let local = edge.toLabelSpace(world)
                let halfLength = hypot(edge.tip.x - edge.from.x, edge.tip.y - edge.from.y) / 2
                // Distance to the line segment.
                let lineDistance = hypot(max(abs(local.x) - halfLength, 0), local.y)

                let size = labelSizes.sizes[relationship.id] ?? CGSize(width: 40, height: 9)
                let labelRect = CGRect(
                    x: EdgeGeometry.labelCenter.x - size.width / 2,
                    y: EdgeGeometry.labelCenter.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                // Distance to the label (zero when inside it).
                let labelDistance = hypot(
                    max(labelRect.minX - local.x, local.x - labelRect.maxX, 0),
                    max(labelRect.minY - local.y, local.y - labelRect.maxY, 0)
                )

                let distance = min(lineDistance, labelDistance)
                return distance <= slop ? (relationship.id, distance) : nil
            }
            .min { $0.distance < $1.distance }
        return relationshipHit.map { .relationship($0.id) }
    }

    /// The node closest to a world point, if the point is within its hit target.
    private func nodeID(atWorld world: CGPoint) -> Int? {
        let positions = simulation.positions
        // Keep targets at least ~14pt on screen even when zoomed far out.
        let nodeTarget = max(nodeRadius, 14 / camera.scale)
        return nodes
            .compactMap { node -> (id: Int, distance: CGFloat)? in
                guard let position = positions[node.id] else { return nil }
                let distance = hypot(position.x - world.x, position.y - world.y)
                return distance <= nodeTarget ? (node.id, distance) : nil
            }
            .min { $0.distance < $1.distance }?
            .id
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

/// What the layout depends on; a change triggers a fresh layout.
private struct LayoutInput: Equatable {
    let nodeIDs: [Int]
    let relationships: [GraphRelationship]
}
