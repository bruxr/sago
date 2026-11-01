//
//  DatabaseView.swift
//  sago
//

import SwiftData
import SwiftUI

/// Main database view: a full-window graph canvas with floating left/right panels on top.
struct DatabaseView: View {
    @State private var showLeftPanel = true
    @State private var showRightPanel = true
    @State private var showQueryPopover = false
    @State private var selection: GraphSelection?

    let connection: ConnectionInfo
    @State private var graph: GraphStore
    var onLogout: () -> Void = {}
    @Environment(\.modelContext) private var modelContext

    private let leftPanelWidth: CGFloat = 260
    private let rightPanelWidth: CGFloat = 300
    private let panelPadding: CGFloat = 10
    private let panelAnimation = Animation.spring(duration: 0.35, bounce: 0.2)

    /// Area covered by the visible panels, so the graph auto-fits between them.
    private var obscuredInsets: EdgeInsets {
        EdgeInsets(
            top: panelPadding,
            leading: showLeftPanel ? leftPanelWidth + panelPadding * 2 : 0,
            bottom: 0,
            trailing: showRightPanel ? rightPanelWidth + panelPadding * 2 : 0
        )
    }

    init(connection: ConnectionInfo, graph: GraphStore, onLogout: @escaping () -> Void = {}) {
        self.connection = connection
        self._graph = State(initialValue: graph)
        self.onLogout = onLogout
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Fills the whole window, including under the toolbar and panels.
                GraphCanvasView(
                    nodes: graph.nodes,
                    relationships: graph.relationships,
                    obscuredInsets: obscuredInsets,
                    selection: $selection
                )

                loadingStatus

                panels
            }
            .task { await graph.load() }
            .onChange(of: selection) {
                // Selecting something reveals its details.
                if selection != nil && !showRightPanel {
                    withAnimation(panelAnimation) { showRightPanel = true }
                }
            }
            .alert("Query Failed", isPresented: isShowingQueryError, presenting: graph.queryError) { _ in
                Button("OK") {}
            } message: { failure in
                Text(failure.message)
            }
            .toolbar { toolbarContent }
            #if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            #else
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Queries

    private var isShowingQueryError: Binding<Bool> {
        Binding(
            get: { graph.queryError != nil },
            set: { if !$0 { graph.queryError = nil } }
        )
    }

    /// Runs a user query, recording it in this server's history if it succeeds.
    /// Returns the error message if it failed.
    private func runQuery(_ cypher: String) async -> String? {
        guard let outcome = await graph.run(cypher) else { return nil }
        switch outcome {
        case .success(let status):
            try? QueryRecord.record(cypher, server: connection.uri, status: status, in: modelContext)
            return nil
        case .failure(let failure):
            return failure.message
        }
    }

    /// Re-runs a query from the history, showing any error in an alert.
    private func rerunQuery(_ cypher: String) {
        guard !graph.isRunningQuery else { return }
        Task {
            if let message = await runQuery(cypher) {
                graph.queryError = GraphStore.QueryFailure(cypher: cypher, message: message)
            }
        }
    }

    // MARK: - Floating panels

    private var panels: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                if showLeftPanel {
                    FloatingPanel(width: leftPanelWidth) {
                        RecentQueriesView(server: connection.uri, runningQuery: graph.runningQuery, onRun: rerunQuery)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Empty space lets gestures pass through to the canvas.
                Spacer(minLength: 0)

                if showRightPanel {
                    FloatingPanel(width: rightPanelWidth) {
                        InspectorView(graph: graph, selection: selection)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(panelPadding)
        }
    }

    /// Spinner while the graph loads, or the error if it failed. Centered in the area between the panels.
    @ViewBuilder
    private var loadingStatus: some View {
        Group {
            if graph.isLoadingGraph {
                ProgressView("Loading graph…")
            } else if let error = graph.loadError, graph.nodes.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't Load Graph", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await graph.load() } }
                }
            }
        }
        .padding(obscuredInsets)
        .animation(panelAnimation, value: obscuredInsets)
    }

    // MARK: - Banner

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(panelAnimation) { showLeftPanel.toggle() }
            } label: {
                Label(showLeftPanel ? "Hide Recent Queries" : "Show Recent Queries", systemImage: "sidebar.leading")
            }
            .help(showLeftPanel ? "Hide Recent Queries" : "Show Recent Queries")
        }

        // Hidden shared background puts the button in its own group; it draws its own glass instead.
        ToolbarItem(placement: .navigation) {
            Button(action: onLogout) {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Log Out")
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .principal) {
            ConnectionPill(connection: connection, isBusy: graph.isRunningQuery)
        }

        ToolbarSpacer(.fixed, placement: .principal)

        ToolbarItem(placement: .principal) {
            Button {
                showQueryPopover.toggle()
            } label: {
                Label("New Query", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .help("New Cypher Query")
            .disabled(graph.isRunningQuery)
            .popover(isPresented: $showQueryPopover, arrowEdge: .bottom) {
                QueryPopover(connection: connection, isRunning: graph.isRunningQuery, onRun: runQuery)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(panelAnimation) { showRightPanel.toggle() }
            } label: {
                Label(showRightPanel ? "Hide Details" : "Show Details", systemImage: "sidebar.trailing")
            }
            .help(showRightPanel ? "Hide Details" : "Show Details")
        }
    }
}

#Preview {
    DatabaseView(connection: PlaceholderData.connection, graph: .preview)
        .frame(minWidth: 1100, minHeight: 700)
        .modelContainer(PlaceholderData.previewContainer)
}
