/// The kind of one responder in the keyboard responder chain, as the launch adapter sees it.
public enum LaunchResponderKind: Sendable, Equatable {
    /// `UIApplication`. Its `openURL:options:completionHandler:` takes an options dictionary.
    case application
    /// `UIScene`. The same selector takes `UIScene.OpenExternalURLOptions`, not a dictionary.
    case scene
    /// Any other responder. It may answer the selector, but its argument types are unknown.
    case other(answersOpenURL: Bool)
}

/// The one call that the launch adapter may make.
public enum AppLaunchTarget: Sendable, Equatable {
    /// Call `UIApplication` at this chain index with an options dictionary.
    case application(index: Int)
    /// Call the typed `UIScene.open(_:options:completionHandler:)` at this chain index.
    case scene(index: Int)
    /// No safe target. Report failure.
    case none
}

public enum AppLaunchTargetRule {
    /// Choose the target by kind, never by "answers the selector". Prefer `UIApplication`
    /// anywhere in the chain, then the first `UIScene`. Never call an unknown responder.
    public static func target(for chain: [LaunchResponderKind]) -> AppLaunchTarget {
        if let index = chain.firstIndex(of: .application) { return .application(index: index) }
        if let index = chain.firstIndex(of: .scene) { return .scene(index: index) }
        return .none
    }
}
