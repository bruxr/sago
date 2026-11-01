//
//  DatabaseView.swift
//  sago
//

import SwiftUI

/// Main database view: a full-window graph canvas with floating left/right panels on top.
struct DatabaseView: View {
    @State private var showLeftPanel = true
    @State private var showRightPanel = true
    @State private var showQueryPopover = false
    @State private var selection: GraphSelection?

    let connection: ConnectionInfo
    var onLogout: () -> Void = {}
    private let recentQueries = PlaceholderData.recentQueries
    @State private var nodes = PlaceholderData.nodes
    private let relationships = PlaceholderData.relationships

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

    var body: some View {
        NavigationStack {
            ZStack {
                // Fills the whole window, including under the toolbar and panels.
                GraphCanvasView(
                    nodes: nodes,
                    relationships: relationships,
                    obscuredInsets: obscuredInsets,
                    selection: $selection
                )

                panels
            }
            .onChange(of: selection) {
                // Selecting something reveals its details.
                if selection != nil && !showRightPanel {
                    withAnimation(panelAnimation) { showRightPanel = true }
                }
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

    // MARK: - Floating panels

    private var panels: some View {
        GlassEffectContainer {
            HStack(spacing: 0) {
                if showLeftPanel {
                    FloatingPanel(width: leftPanelWidth) {
                        RecentQueriesView(queries: recentQueries)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Empty space lets gestures pass through to the canvas.
                Spacer(minLength: 0)

                if showRightPanel {
                    FloatingPanel(width: rightPanelWidth) {
                        InspectorView(nodes: $nodes, relationships: relationships, selection: selection)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(panelPadding)
        }
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
            ConnectionPill(connection: connection)
        }

        ToolbarSpacer(.fixed, placement: .principal)

        ToolbarItem(placement: .principal) {
            Button {
                showQueryPopover.toggle()
            } label: {
                Label("New Query", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .help("New Cypher Query")
            .popover(isPresented: $showQueryPopover, arrowEdge: .bottom) {
                QueryPopover(connection: connection)
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
    DatabaseView(connection: PlaceholderData.connection)
        .frame(minWidth: 1100, minHeight: 700)
}
