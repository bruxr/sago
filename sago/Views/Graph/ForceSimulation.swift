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
    private var velocities: [Int: CGVector] = [:]
    private var nodeIDs: [Int] = []
    private var edges: [(Int, Int)] = []
    /// Nodes placed by the user. They keep their position and are not moved by forces.
    private var pinned: Set<Int> = []

    private(set) var isSettled = false
    private var lastDate: Date?
    private var accumulator: TimeInterval = 0
    private var stepCount = 0

    // Tuning constants (units are points per step).
    private let repulsion: CGFloat = 250
    private let springLength: CGFloat = 130
    private let springStiffness: CGFloat = 0.04
    private let gravity: CGFloat = 0.012
    /// Velocity retained each step. Damped enough that nodes glide into place without bouncing.
    private let friction: CGFloat = 0.8
    private let stepInterval: TimeInterval = 1.0 / 60.0
    private let maxSteps = 1800

    init(nodes: [GraphNode], relationships: [GraphRelationship]) {
        load(nodes: nodes, relationships: relationships)
    }

    /// Replaces the graph and computes its settled layout up front, so it can be shown
    /// in its final arrangement instead of animating into place.
    func load(nodes: [GraphNode], relationships: [GraphRelationship]) {
        nodeIDs = nodes.map(\.id)
        let known = Set(nodeIDs)
        edges = relationships
            .filter { known.contains($0.startNodeID) && known.contains($0.endNodeID) }
            .map { ($0.startNodeID, $0.endNodeID) }

        positions = [:]
        velocities = [:]
        pinned = []
        for (index, id) in nodeIDs.enumerated() {
            // Phyllotaxis spiral gives a deterministic, evenly spread starting cluster.
            let angle = Double(index) * 2.399963
            let radius = 6.0 * sqrt(Double(index) + 0.5)
            positions[id] = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            velocities[id] = .zero
        }

        // Run the layout to completion now.
        stepCount = 0
        while stepCount < maxSteps && !isSettledNow() {
            step()
        }
        isSettled = true
        lastDate = nil
        accumulator = 0
    }

    /// Moves a node to `point` and pins it there; the rest of the graph reacts to the new position.
    func move(_ id: Int, to point: CGPoint) {
        guard positions[id] != nil else { return }
        positions[id] = point
        velocities[id] = .zero
        pinned.insert(id)
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
        stepCount = 0
    }

    /// Advances the simulation up to `date`.
    func advance(to date: Date) {
        guard !isSettled else { return }
        defer { lastDate = date }
        guard let lastDate else {
            step()
            isSettled = isSettledNow()
            return
        }

        // Clamp to avoid a large jump after the app was in the background.
        accumulator += min(date.timeIntervalSince(lastDate), 0.1)
        while accumulator >= stepInterval {
            step()
            accumulator -= stepInterval
            isSettled = isSettledNow()
            if isSettled { break }
        }
    }

    private var lastMaxSpeed: CGFloat = .infinity

    private func isSettledNow() -> Bool {
        (stepCount > 60 && lastMaxSpeed < 0.02) || stepCount >= maxSteps
    }

    private func step() {
        var forces = [Int: CGVector](minimumCapacity: nodeIDs.count)
        for id in nodeIDs { forces[id] = .zero }

        // Repulsion between every pair of nodes.
        for i in nodeIDs.indices {
            for j in nodeIDs.indices where j > i {
                let a = nodeIDs[i], b = nodeIDs[j]
                guard let pa = positions[a], let pb = positions[b] else { continue }
                var dx = pa.x - pb.x
                var dy = pa.y - pb.y
                if dx == 0 && dy == 0 {
                    dx = CGFloat.random(in: -1...1)
                    dy = CGFloat.random(in: -1...1)
                }
                let distance = max(sqrt(dx * dx + dy * dy), 10)
                // Force falls off with distance.
                let magnitude = repulsion / distance
                let fx = dx / distance * magnitude
                let fy = dy / distance * magnitude
                forces[a]?.dx += fx
                forces[a]?.dy += fy
                forces[b]?.dx -= fx
                forces[b]?.dy -= fy
            }
        }

        // Springs along relationships.
        for (a, b) in edges {
            guard let pa = positions[a], let pb = positions[b] else { continue }
            let dx = pb.x - pa.x
            let dy = pb.y - pa.y
            let distance = max(sqrt(dx * dx + dy * dy), 0.01)
            let displacement = (distance - springLength) * springStiffness
            let fx = dx / distance * displacement
            let fy = dy / distance * displacement
            forces[a]?.dx += fx
            forces[a]?.dy += fy
            forces[b]?.dx -= fx
            forces[b]?.dy -= fy
        }

        // Integrate.
        var maxSpeed: CGFloat = 0
        for id in nodeIDs where !pinned.contains(id) {
            guard var position = positions[id], var velocity = velocities[id], let force = forces[id] else { continue }
            velocity.dx = (velocity.dx + force.dx - position.x * gravity) * friction
            velocity.dy = (velocity.dy + force.dy - position.y * gravity) * friction
            position.x += velocity.dx
            position.y += velocity.dy
            positions[id] = position
            velocities[id] = velocity
            maxSpeed = max(maxSpeed, hypot(velocity.dx, velocity.dy))
        }

        stepCount += 1
        lastMaxSpeed = maxSpeed
    }

    /// Bounding box of all node centers, in world coordinates.
    var boundingBox: CGRect {
        let points = positions.values
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
