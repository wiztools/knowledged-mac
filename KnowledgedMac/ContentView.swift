import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case post     = "Post"
    case retrieve = "Retrieve"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .post:     return "square.and.pencil"
        case .retrieve: return "magnifyingglass"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var client:   KnowledgedClient
    @EnvironmentObject private var settings: AppSettings
    @State private var selection: SidebarItem = .post

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 180)
        } detail: {
            Group {
                switch selection {
                case .post:     PostView()
                case .retrieve: RetrieveView()
                }
            }
            // Give each detail pane a consistent minimum size.
            .frame(minWidth: 500, minHeight: 420)
        }
        .navigationTitle("Knowledged")
    }
}
