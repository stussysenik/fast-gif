import SwiftUI

/// The root view — iA Writer simplicity.
/// Three states: Empty → Import → Edit.
/// No chrome, no clutter. Just your GIF.
struct ContentView: View {
    @State private var project = GIFProject()
    @State private var selectedTab: Tab = .create

    enum Tab: String, CaseIterable {
        case create = "Create"
        case batch = "Batch"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                Group {
                    if project.hasFrames {
                        EditorView(project: project)
                    } else {
                        ImportView(project: project)
                    }
                }
                .navigationTitle("FastGIF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if project.hasFrames {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("New", systemImage: "plus") {
                                project.reset()
                            }
                        }
                    }
                }
            }
            .tabItem {
                Label("Create", systemImage: "wand.and.stars")
            }
            .tag(Tab.create)

            BatchView(project: project)
                .tabItem {
                    Label("Batch", systemImage: "square.stack.3d.up")
                }
                .tag(Tab.batch)
        }
    }
}

#Preview {
    ContentView()
}
