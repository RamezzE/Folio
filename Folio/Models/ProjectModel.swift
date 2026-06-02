import Foundation
import AppKit

enum ProjectType: String, Codable, CaseIterable {
    // JavaScript / Web frameworks
    case react = "react"
    case vue = "vue"
    case nextjs = "nextjs"
    case nuxt = "nuxt"
    case svelte = "svelte"
    case angular = "angular"
    case node = "node"
    // Backend languages
    case python = "python"
    case django = "django"
    case go = "go"
    case rust = "rust"
    case java = "java"
    case kotlin = "kotlin"
    case csharp = "csharp"
    case ruby = "ruby"
    case php = "php"
    case elixir = "elixir"
    case cpp = "cpp"
    // Mobile
    case ios = "ios"
    case android = "android"
    case flutter = "flutter"
    // Infrastructure
    case docker = "docker"
    case terraform = "terraform"
    // Cloud services
    case firebase = "firebase"
    case supabase = "supabase"
    // Other
    case git = "git"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .react:     return "React"
        case .vue:       return "Vue"
        case .nextjs:    return "Next.js"
        case .nuxt:      return "Nuxt"
        case .svelte:    return "Svelte"
        case .angular:   return "Angular"
        case .node:      return "Node.js"
        case .python:    return "Python"
        case .django:    return "Django"
        case .go:        return "Go"
        case .rust:      return "Rust"
        case .java:      return "Java"
        case .kotlin:    return "Kotlin"
        case .csharp:    return "C# / .NET"
        case .ruby:      return "Ruby"
        case .php:       return "PHP"
        case .elixir:    return "Elixir"
        case .cpp:       return "C / C++"
        case .ios:       return "iOS / Swift"
        case .android:   return "Android"
        case .flutter:   return "Flutter"
        case .docker:    return "Docker"
        case .terraform: return "Terraform"
        case .firebase:  return "Firebase"
        case .supabase:  return "Supabase"
        case .git:       return "Git"
        case .unknown:   return "Unknown"
        }
    }

    var systemIcon: String {
        switch self {
        case .react, .vue, .nextjs, .nuxt, .svelte, .angular, .node:
            return "chevron.left.forwardslash.chevron.right"
        case .python, .django: return "snake"
        case .go:        return "hare"
        case .rust:      return "gear"
        case .java, .kotlin: return "cup.and.saucer"
        case .csharp:    return "dot.square"
        case .ruby:      return "diamond"
        case .php:       return "globe"
        case .elixir:    return "sparkles"
        case .cpp:       return "c.square"
        case .ios:       return "apple.logo"
        case .android:   return "square.and.arrow.up"
        case .flutter:   return "bird"
        case .docker:    return "shippingbox"
        case .terraform: return "server.rack"
        case .firebase:  return "flame"
        case .supabase:  return "bolt.fill"
        case .git:       return "arrow.triangle.branch"
        case .unknown:   return "folder"
        }
    }
}

struct ProjectModel: Identifiable, Codable, Equatable {
    let id: UUID
    var url: URL
    var name: String
    var type: ProjectType
    var appliedIconID: UUID?
    var lastScanned: Date

    init(url: URL, type: ProjectType, appliedIconID: UUID? = nil) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.type = type
        self.appliedIconID = appliedIconID
        self.lastScanned = Date()
    }
}
