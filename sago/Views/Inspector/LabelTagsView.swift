//
//  LabelTagsView.swift
//  sago
//

import SwiftUI

/// A node's labels as Liquid Glass capsules. Tap a label to reveal its remove button; (+) adds a new one.
struct LabelTagsView: View {
    @Binding var labels: [String]

    @State private var selectedLabel: String?
    @State private var isAdding = false
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(labels, id: \.self) { label in
                    tag(label)
                }
                addButton
            }
        }
    }

    private func tag(_ label: String) -> some View {
        let isSelected = selectedLabel == label
        return HStack(spacing: 4) {
            Text(label)
                .font(.headline)
            if isSelected {
                Button {
                    remove(label)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .help("Remove Label")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(GraphPalette.color(for: label).opacity(0.5)).interactive(), in: .capsule)
        .glassEffectID(label, in: glassNamespace)
        // Fade the glass with the puff instead of morphing it into a neighboring tag.
        .glassEffectTransition(.materialize)
        .transition(AsymmetricTransition(insertion: .scale.combined(with: .opacity), removal: PuffTransition()))
        .contentShape(.capsule)
        .onTapGesture {
            withAnimation(.snappy) {
                selectedLabel = isSelected ? nil : label
            }
        }
        .contextMenu {
            Button("Remove Label", systemImage: "minus.circle", role: .destructive) {
                remove(label)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Remove") { remove(label) }
    }

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Label("Add Label", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.headline)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .glassEffectID("add", in: glassNamespace)
        .help("Add Label")
        .popover(isPresented: $isAdding, arrowEdge: .bottom) {
            AddLabelPopover(existingLabels: labels) { newLabel in
                withAnimation(.snappy) {
                    labels.append(newLabel)
                    selectedLabel = nil
                }
            }
        }
    }

    private func remove(_ label: String) {
        withAnimation(.snappy) {
            labels.removeAll { $0 == label }
            selectedLabel = nil
        }
    }
}

/// Removal "puff": the view swells, blurs and fades away. Falls back to a fade when Reduce Motion is on.
private struct PuffTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 1.4)
            .blur(radius: phase.isIdentity ? 0 : 6)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// Text field for naming a new label. Rejects empty names and labels the node already has.
private struct AddLabelPopover: View {
    let existingLabels: [String]
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        existingLabels.contains(trimmedName)
    }

    private var canAdd: Bool {
        !trimmedName.isEmpty && !isDuplicate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Label")
                .font(.headline)

            TextField("Label", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(add)

            if isDuplicate {
                Text("Node already has this label")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(14)
        .frame(width: 240)
        .onAppear { isFocused = true }
    }

    private func add() {
        guard canAdd else { return }
        onAdd(trimmedName)
        dismiss()
    }
}

#Preview {
    @Previewable @State var labels = ["Person", "Director", "Writer", "Producer", "Screenwriter"]
    LabelTagsView(labels: $labels)
        .padding()
        .frame(width: 300)
}
