//
//  InspectorView.swift
//  sago
//

import SwiftUI

/// Right panel showing details about the current graph or the selected node / relationship.
struct InspectorView: View {
    @Bindable var graph: GraphStore
    let selection: GraphSelection?

    /// Selection whose properties failed to load, and why.
    @State private var failure: (selection: GraphSelection, message: String)?

    /// Properties of the selected element, `nil` while they're being fetched.
    private var properties: [String: PropertyValue]? {
        selection.flatMap(graph.cachedProperties(for:))
    }

    private var propertiesError: String? {
        failure?.selection == selection ? failure?.message : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch selection {
                case .node(let id):
                    if let index = graph.nodes.firstIndex(where: { $0.id == id }) {
                        nodeDetails(index)
                    }
                case .relationship(let id):
                    if let relationship = graph.relationships.first(where: { $0.id == id }) {
                        relationshipDetails(relationship)
                    }
                case nil:
                    summary
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Swap content instantly. Fading text fields in/out over the glass panel renders them black mid-transition.
            .transaction(value: selection) { $0.animation = nil }
        }
        .task(id: selection) { await loadProperties() }
    }

    /// Fetches the selected element's properties. Cancelled automatically when the selection changes.
    /// The store caches the result, which `properties` then reads.
    private func loadProperties() async {
        guard let selection, graph.cachedProperties(for: selection) == nil else { return }
        do {
            _ = try await graph.properties(for: selection)
        } catch is CancellationError {
        } catch {
            failure = (selection, (error as? AuthError)?.message ?? error.localizedDescription)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Database")
                .font(.headline)
            HStack(spacing: 10) {
                statTile(title: "Nodes", count: graph.nodeCount, systemImage: "circle.hexagongrid")
                statTile(title: "Relationships", count: graph.relationshipCount, systemImage: "arrow.triangle.branch")
            }
            if isShowingSubset {
                Text("Showing \(graph.nodes.count, format: .number) nodes and \(graph.relationships.count, format: .number) relationships.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Whether the canvas shows fewer elements than the database holds.
    private var isShowingSubset: Bool {
        guard let nodeCount = graph.nodeCount, let relationshipCount = graph.relationshipCount else { return false }
        return graph.nodes.count < nodeCount || graph.relationships.count < relationshipCount
    }

    private func statTile(title: String, count: Int?, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                if let count {
                    Text(count, format: .number)
                } else {
                    // Keeps the tile height while the totals load.
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxHeight: .infinity, alignment: .leading)
                }
            }
            .font(.title2.monospacedDigit())
            .fontWeight(.semibold)
            .frame(height: 28, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }

    private func nodeDetails(_ index: Int) -> some View {
        let node = graph.nodes[index]
        return VStack(alignment: .leading, spacing: 14) {
            LabelTagsView(labels: $graph.nodes[index].labels)
                // Fresh tag selection for each node.
                .id(node.id)
            Text(node.caption)
                .font(.headline)

            fieldRows(id: node.id)
        }
    }

    private func relationshipDetails(_ relationship: GraphRelationship) -> some View {
        let start = graph.nodes.first { $0.id == relationship.startNodeID }?.caption ?? "\(relationship.startNodeID)"
        let end = graph.nodes.first { $0.id == relationship.endNodeID }?.caption ?? "\(relationship.endNodeID)"
        return VStack(alignment: .leading, spacing: 14) {
            tag(relationship.type, color: .gray)
            HStack(spacing: 6) {
                Text(start)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(end)
            }
            .font(.headline)

            fieldRows(id: relationship.id)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.headline)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            // Same glass capsule as node labels; not interactive since relationship types can't be edited.
            .glassEffect(.regular.tint(color.opacity(0.5)), in: .capsule)
    }

    /// The fields once loaded; a spinner while they're being fetched.
    @ViewBuilder
    private func fieldRows(id: Int) -> some View {
        if let properties {
            ForEach(Self.orderedFields(id: id, properties: properties), id: \.key) { field in
                PropertyRow(key: field.key, value: field.value)
            }
        } else if let propertiesError {
            PropertyRow(key: "<id>", value: String(id))
            Label(propertiesError, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            PropertyRow(key: "<id>", value: String(id))
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    /// `<id>` first, then `id` (if present), then remaining fields alphabetically.
    static func orderedFields(id: Int, properties: [String: PropertyValue]) -> [(key: String, value: String)] {
        var fields: [(key: String, value: String)] = [("<id>", String(id))]
        if let id = properties["id"] {
            fields.append(("id", id.displayString))
        }
        let rest = properties
            .filter { $0.key != "id" }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { (key: $0.key, value: $0.value.displayString) }
        return fields + rest
    }
}

/// Lays subviews out left to right, wrapping to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(for: subviews, maxWidth: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(for subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var rowStart = 0

        // Vertically centers the items of the finished row within its height.
        func centerRow() {
            for index in rowStart..<frames.count {
                frames[index].origin.y += (rowHeight - frames[index].height) / 2
            }
        }

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > maxWidth {
                centerRow()
                origin = CGPoint(x: 0, y: origin.y + rowHeight + spacing)
                rowHeight = 0
                rowStart = frames.count
            }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        centerRow()
        return frames
    }
}

#Preview("Summary") {
    InspectorView(graph: .preview, selection: nil)
        .frame(width: 300, height: 500)
}

#Preview("Node") {
    InspectorView(graph: .preview, selection: .node(10))
        .frame(width: 300, height: 600)
}

#Preview("Relationship") {
    InspectorView(graph: .preview, selection: .relationship(100))
        .frame(width: 300, height: 400)
}
