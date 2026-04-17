import Foundation

class NavigationState: ObservableObject {
    @Published var selection: SidebarItem = .post
    @Published var retrieveFilePath: String? = nil
}
