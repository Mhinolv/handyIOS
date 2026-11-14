import UIKit

@MainActor
protocol KeyboardAppLaunching {
    func open(_ url: URL, from responder: UIResponder, completion: @escaping @MainActor (Bool) -> Void)
}

/// Owner-approved device experiment. This invokes the public UIApplication URL method
/// through the responder chain because keyboards have no supported app-launch API.
/// Keep this workaround here so another launch path can replace it.
struct ResponderChainAppLauncher: KeyboardAppLaunching {
    func open(_ url: URL, from responder: UIResponder, completion: @escaping @MainActor (Bool) -> Void) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var current: UIResponder? = responder
        while let candidate = current {
            if candidate.responds(to: selector) {
                typealias Open = @convention(c) (
                    AnyObject, Selector, NSURL, NSDictionary, @convention(block) (Bool) -> Void
                ) -> Void
                let method = unsafeBitCast(candidate.method(for: selector), to: Open.self)
                method(candidate, selector, url as NSURL, [:] as NSDictionary, { success in
                    Task { @MainActor in completion(success) }
                })
                return
            }
            current = candidate.next
        }
        completion(false)
    }
}
