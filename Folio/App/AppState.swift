import SwiftUI
import Combine

// SidebarItem is defined in Models/SidebarItem.swift
class AppState: ObservableObject {
    static let shared = AppState()
    @Published var selectedTab: SidebarItem = .dashboard
    @Published var showSettings = false
    /// Called by AppDelegate.applicationWillTerminate to cancel any in-flight apply task.
    var terminationHandler: (() -> Void)?
}
