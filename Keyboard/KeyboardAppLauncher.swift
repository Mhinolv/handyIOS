import HandyKit
import UIKit

@MainActor
protocol KeyboardAppLaunching {
    func open(_ url: URL, from responder: UIResponder, completion: @escaping @MainActor (Bool) -> Void)
}

/// Owner-approved device experiment. This invokes the public UIApplication URL method
/// through the responder chain because keyboards have no supported app-launch API.
/// Keep this workaround here so another launch path can replace it.
/// #31: the target is chosen by class. Each target gets only the options type that it takes.
struct ResponderChainAppLauncher: KeyboardAppLaunching {
    func open(_ url: URL, from responder: UIResponder, completion: @escaping @MainActor (Bool) -> Void) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        let applicationClass: AnyClass? = NSClassFromString("UIApplication")
        let chain = Array(sequence(first: responder, next: { $0.next }))
        let kinds = chain.map { candidate -> LaunchResponderKind in
            if let applicationClass, candidate.isKind(of: applicationClass) { return .application }
            if candidate is UIScene { return .scene }
            return .other(answersOpenURL: candidate.responds(to: selector))
        }
        let reply: @convention(block) (Bool) -> Void = { success in
            Task { @MainActor in completion(success) }
        }
        switch AppLaunchTargetRule.target(for: kinds) {
        case .application(let index):
            let application = chain[index]
            guard application.responds(to: selector) else { completion(false); return }
            typealias Open = @convention(c) (
                AnyObject, Selector, NSURL, NSDictionary, @convention(block) (Bool) -> Void
            ) -> Void
            let method = unsafeBitCast(application.method(for: selector), to: Open.self)
            method(application, selector, url as NSURL, [:] as NSDictionary, reply)
        case .scene(let index):
            guard let scene = chain[index] as? UIScene else { completion(false); return }
            scene.open(url, options: UIScene.OpenExternalURLOptions(), completionHandler: reply)
        case .none:
            completion(false)
        }
    }
}
