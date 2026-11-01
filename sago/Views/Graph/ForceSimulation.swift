//
//  ForceSimulation.swift
//  sago
//

import SwiftUI

/// A simple force-directed layout: nodes repel each other, relationships act as springs,
/// and a weak gravity pulls everything toward the origin.
///
/// Positions are in "world" coordinates centered on (0, 0). The simulation advances in
/// fixed steps so the motion looks the same regardless of frame rate.
final class ForceSimulation {
    private(set) var positions: [Int: CGPoint] = [:]
    private var layout = ForceLayout(nodeIDs: [], edges: [])
    private var indexByID: [Int: Int] = [:]

    private(set) var isSettled = true
    private var lastDate: Date?
    private var accumulator: TimeInterval = 0
    private let stepInterval: TimeInterval = 1.0 / 60.0

    /// Replaces the graph with its settled layout, computed up front off the main thread so it can be
    /// shown in its final arrangement instead of animating into place. Does nothing if cancelled.
    func load(nodes: [GraphNode], relationships: [GraphRelationship]) async {
        let nodeIDs = nodes.map(\.id)
        let known = Set(nodeIDs)
        let edges = relationships
            .filter { known.contains($0.startNodeID) && known.contains($0.endNodeID) }
            .map { ($0.startNodeID, $0.endNodeID) }

        guard let settled = await Self.settledLayout(nodeIDs: nodeIDs, edges: edges) else { return }
        layout = settled
        indexByID = Dictionary(uniqueKeysWithValues: nodeIDs.enumerated().map { ($1, $0) })
        isSettled = true
        lastDate = nil
        accumulator = 0
        syncPositions()
    }

    /// Runs the layout to completion on a background thread; `nil` if the calling task is cancelled.
    @concurrent
    private nonisolated static func settledLayout(nodeIDs: [Int], edges: [(Int, Int)]) async -> ForceLayout? {
        var layout = ForceLayout(nodeIDs: nodeIDs, edges: edges)
        while !layout.isSettled {
            if Task.isCancelled { return nil }
            layout.step()
        }
        return layout
    }

    /// Moves a node to `point` and pins it there; the rest of the graph reacts to the new position.
    func move(_ id: Int, to point: CGPoint) {
        guard let index = indexByID[id] else { return }
        layout.pin(index, at: point)
        positions[id] = point
        reheat()
    }

    /// Wakes the simulation so it continues to animate.
    func reheat() {
        if isSettled {
            // Start a fresh clock; keep it running if the simulation is already active.
            lastDate = nil
            accumulator = 0
        }
        isSettled = false
        layout.reheat()
    }

    /// Advances the simulation up to `date`.
    func advance(to date: Date) {
        guard !isSettled else { return }
        defer {
            lastDate = date
            syncPositions()
        }
        guard let lastDate else {
            layout.step()
            isSettled = layout.isSettled
            return
        }

        // Clamp to avoid a large jump after the app was in the background.
        accumulator += min(date.timeIntervalSince(lastDate), 0.1)
        while accumulator >= stepInterval {
            layout.step()
            accumulator -= stepInterval
            isSettled = layout.isSettled
            if isSettled { break }
        }
    }

    private func syncPositions() {
        positions = Dictionary(uniqueKeysWithValues: zip(layout.nodeIDs, layout.positions))
    }

    /// Bounding box of all node centers, in world coordinates.
    var boundingBox: CGRect {
        let points = layout.positions
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// The physics behind `ForceSimulation`. A value type so the initial layout can run off the main actor.
/// Nodes are addressed by index into the arrays.
nonisolated struct ForceLayout: Sendable {
    let nodeIDs: [Int]
    private(set) var positions: [CGPoint]
    private var velocities: [CGVector]
    private let edges: [(Int, Int)]
    /// Nodes placed by the user. They keep their position and are not moved by forces.
    private var pinned: [Bool]
    private var stepCount = 0
    private var lastMaxSpeed: CGFloat = .infinity
    /// "Temperature" scaling all forces. Cools each step so even large graphs settle in a few hundred steps.
    private var alpha: CGFloat = 1

    // Tuning constants (units are points per step).
    private let repulsion: CGFloat = 250
    private let springLength: CGFloat = 130
    private let springStiffness: CGFloat = 0.04
    private let gravity: CGFloat = 0.012
    /// Velocity retained each step. Damped enough that nodes glide into place without bouncing.
    private let friction: CGFloat = 0.8
    private let maxSteps = 1800
    /// Barnes–Hut accuracy: cells smaller than `theta` × their distance are treated as a single body.
    private let theta: CGFloat = 0.8
    private let alphaMin: CGFloat = 0.001
    /// Cools from 1 to `alphaMin` in 300 steps.
    private let alphaDecay: CGFloat = 1 - pow(0.001, 1.0 / 300)
    /// Temperature after a drag: enough for neighbors to follow, without re-scrambling the graph.
    private let reheatAlpha: CGFloat = 0.3

    init(nodeIDs: [Int], edges: [(Int, Int)]) {
        self.nodeIDs = nodeIDs
        let indexByID = Dictionary(uniqueKeysWithValues: nodeIDs.enumerated().map { ($1, $0) })
        self.edges = edges.compactMap { a, b in
            guard let a = indexByID[a], let b = indexByID[b] else { return nil }
            return (a, b)
        }
        // Phyllotaxis spiral gives a deterministic, evenly spread starting cluster.
        positions = nodeIDs.indices.map { index in
            let angle = Double(index) * 2.399963
            let radius = 6.0 * sqrt(Double(index) + 0.5)
            return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
        velocities = Array(repeating: .zero, count: nodeIDs.count)
        pinned = Array(repeating: false, count: nodeIDs.count)
    }

    var isSettled: Bool {
        (stepCount > 60 && lastMaxSpeed < 0.02) || alpha < alphaMin || stepCount >= maxSteps
    }

    mutating func pin(_ index: Int, at point: CGPoint) {
        positions[index] = point
        velocities[index] = .zero
        pinned[index] = true
    }

    mutating func reheat() {
        stepCount = 0
        alpha = max(alpha, reheatAlpha)
    }

    mutating func step() {
        var forces = repulsionForces()

        // Springs along relationships.
        for (a, b) in edges {
            let pa = positions[a], pb = positions[b]
            let dx = pb.x - pa.x
            let dy = pb.y - pa.y
            let distance = max(sqrt(dx * dx + dy * dy), 0.01)
            let displacement = (distance - springLength) * springStiffness
            let fx = dx / distance * displacement
            let fy = dy / distance * displacement
            forces[a].dx += fx
            forces[a].dy += fy
            forces[b].dx -= fx
            forces[b].dy -= fy
        }

        // Integrate.
        var maxSpeed: CGFloat = 0
        for index in positions.indices where !pinned[index] {
            var velocity = velocities[index]
            let position = positions[index]
            velocity.dx = (velocity.dx + (forces[index].dx - position.x * gravity) * alpha) * friction
            velocity.dy = (velocity.dy + (forces[index].dy - position.y * gravity) * alpha) * friction
            positions[index].x += velocity.dx
            positions[index].y += velocity.dy
            velocities[index] = velocity
            maxSpeed = max(maxSpeed, hypot(velocity.dx, velocity.dy))
        }

        stepCount += 1
        lastMaxSpeed = maxSpeed
        alpha *= 1 - alphaDecay
    }

    /// Repulsion between every pair of nodes, approximated with a Barnes–Hut quadtree (O(n log n)).
    /// Force falls off with distance.
    private func repulsionForces() -> [CGVector] {
        var forces = Array(repeating: CGVector.zero, count: positions.count)
        guard positions.count > 1 else { return forces }
        let tree = QuadTree(positions: positions)
        let thetaSquared = theta * theta
        var stack: [Int] = []
        stack.reserveCapacity(64)
        // Unsafe buffers keep the hot loop fast in debug builds too.
        tree.cells.withUnsafeBufferPointer { cells in
            positions.withUnsafeBufferPointer { positions in
                forces.withUnsafeMutableBufferPointer { forces in
                    for index in positions.indices {
                        let p = positions[index]
                        var fx: CGFloat = 0, fy: CGFloat = 0
                        stack.removeAll(keepingCapacity: true)
                        stack.append(0)
                        while let cellIndex = stack.popLast() {
                            let cell = cells[cellIndex]
                            guard cell.mass > 0, !(cell.firstChild < 0 && cell.body == index) else { continue }
                            var dx = p.x - cell.sumX / cell.mass
                            var dy = p.y - cell.sumY / cell.mass
                            let distanceSquared = dx * dx + dy * dy
                            if cell.firstChild < 0 || cell.size * cell.size < thetaSquared * distanceSquared {
                                if distanceSquared == 0 {
                                    dx = CGFloat.random(in: -1...1)
                                    dy = CGFloat.random(in: -1...1)
                                }
                                let distance = max(sqrt(dx * dx + dy * dy), 10)
                                let magnitude = repulsion * cell.mass / (distance * distance)
                                fx += dx * magnitude
                                fy += dy * magnitude
                            } else {
                                let first = cell.firstChild
                                stack.append(first)
                                stack.append(first + 1)
                                stack.append(first + 2)
                                stack.append(first + 3)
                            }
                        }
                        forces[index] = CGVector(dx: fx, dy: fy)
                    }
                }
            }
        }
        return forces
    }
}

/// A quadtree storing each cell's node count and position sum, for Barnes–Hut repulsion.
private nonisolated struct QuadTree {
    struct Cell {
        var minX: CGFloat
        var minY: CGFloat
        var size: CGFloat
        var mass: CGFloat = 0
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        /// Index of the first of four children, or -1 for a leaf.
        var firstChild = -1
        /// The single node in a leaf, or -1 if empty or holding several coincident nodes.
        var body = -1

        var isLeaf: Bool { firstChild < 0 }
    }

    private(set) var cells: [Cell] = []
    /// Bounds recursion when nodes (nearly) coincide; such nodes share a leaf.
    private let maxDepth = 24

    init(positions: [CGPoint]) {
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for p in positions {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let size = max(maxX - minX, maxY - minY, 1)
        cells.reserveCapacity(positions.count * 2)
        cells.append(Cell(minX: minX, minY: minY, size: size))
        for index in positions.indices {
            insert(index, at: positions[index], into: 0, depth: 0, positions: positions)
        }
    }

    private mutating func insert(_ body: Int, at p: CGPoint, into cellIndex: Int, depth: Int, positions: [CGPoint]) {
        cells[cellIndex].mass += 1
        cells[cellIndex].sumX += p.x
        cells[cellIndex].sumY += p.y

        if !cells[cellIndex].isLeaf {
            insert(body, at: p, into: child(of: cellIndex, containing: p), depth: depth + 1, positions: positions)
            return
        }
        if cells[cellIndex].mass == 1 {
            cells[cellIndex].body = body
            return
        }
        guard depth < maxDepth else {
            cells[cellIndex].body = -1
            return
        }

        // Split the leaf and push both its previous node and the new one down.
        let existing = cells[cellIndex].body
        cells[cellIndex].body = -1
        let parent = cells[cellIndex]
        let half = parent.size / 2
        cells[cellIndex].firstChild = cells.count
        for quadrant in 0..<4 {
            cells.append(Cell(
                minX: parent.minX + (quadrant % 2 == 0 ? 0 : half),
                minY: parent.minY + (quadrant < 2 ? 0 : half),
                size: half
            ))
        }
        if existing >= 0 {
            let q = positions[existing]
            insert(existing, at: q, into: child(of: cellIndex, containing: q), depth: depth + 1, positions: positions)
        }
        insert(body, at: p, into: child(of: cellIndex, containing: p), depth: depth + 1, positions: positions)
    }

    private func child(of cellIndex: Int, containing p: CGPoint) -> Int {
        let cell = cells[cellIndex]
        let half = cell.size / 2
        let right = p.x >= cell.minX + half ? 1 : 0
        let bottom = p.y >= cell.minY + half ? 2 : 0
        return cell.firstChild + right + bottom
    }
}
