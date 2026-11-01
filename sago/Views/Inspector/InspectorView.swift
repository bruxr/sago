//
//  InspectorView.swift
//  sago
//

import SwiftUI

/// Right panel showing details about the current graph or the selected node / relationship.
struct InspectorView: View {
    let nodes: [GraphNode]
    let relationships: [GraphRelationship]
    let selection: GraphSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch selection {
                case .node(let id):
                    if let node = nodes.first(where: { $0.id == id }) {
                        nodeDetails(node)
                    }
                case .relationship(let id):
                    if let relationship = relationships.first(where: { $0.id == id }) {
                        relationshipDetails(relationship)
                    }
                case nil:
                    summary
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.snappy, value: selection)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Result")
                .font(.headline)
            HStack(spacing: 10) {
                statTile(title: "Nodes", count: nodes.count, systemImage: "circle.hexagongrid")
                statTile(title: "Relationships", count: relationships.count, systemImage: "arrow.triangle.branch")
            }
        }
    }

    private func statTile(title: String, count: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(count, format: .number)
                .font(.title2.monospacedDigit())
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }

    private func nodeDetails(_ node: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(node.labels, id: \.self) { label in
                    tag(label, color: GraphPalette.color(for: label))
                }
            }
            Text(node.caption)
                .font(.headline)

            fieldRows(id: node.id, properties: node.properties)
        }
    }

    private func relationshipDetails(_ relationship: GraphRelationship) -> some View {
        let start = nodes.first { $0.id == relationship.startNodeID }?.caption ?? "\(relationship.startNodeID)"
        let end = nodes.first { $0.id == relationship.endNodeID }?.caption ?? "\(relationship.endNodeID)"
        return VStack(alignment: .leading, spacing: 14) {
            tag(relationship.type, color: .gray)
            HStack(spacing: 6) {
                Text(start)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(end)
            }
            .font(.headline)

            fieldRows(id: relationship.id, properties: relationship.properties)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.25), in: .capsule)
    }

    private func fieldRows(id: Int, properties: [String: PropertyValue]) -> some View {
        ForEach(Self.orderedFields(id: id, properties: properties), id: \.key) { field in
            PropertyRow(key: field.key, value: field.value)
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

#Preview("Summary") {
    InspectorView(nodes: PlaceholderData.nodes, relationships: PlaceholderData.relationships, selection: nil)
        .frame(width: 300, height: 500)
}

#Preview("Node") {
    InspectorView(nodes: PlaceholderData.nodes, relationships: PlaceholderData.relationships, selection: .node(10))
        .frame(width: 300, height: 600)
}

#Preview("Relationship") {
    InspectorView(nodes: PlaceholderData.nodes, relationships: PlaceholderData.relationships, selection: .relationship(100))
        .frame(width: 300, height: 400)
}
