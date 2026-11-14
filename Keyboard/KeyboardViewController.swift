import HandyKit
import UIKit

final class KeyboardViewController: UIInputViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let title = UILabel()
        title.text = "\(HandyConfiguration.displayName) — dictation is not available yet."
        title.numberOfLines = 0
        title.textAlignment = .center
        title.font = .preferredFont(forTextStyle: .body)
        title.adjustsFontForContentSizeCategory = true

        let nextKeyboard = UIButton(type: .system)
        nextKeyboard.setTitle("Next keyboard", for: .normal)
        nextKeyboard.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let stack = UIStackView(arrangedSubviews: [title, nextKeyboard])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }
}
