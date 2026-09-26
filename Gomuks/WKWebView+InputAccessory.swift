import ObjectiveC
import UIKit
import WebKit

extension WKWebView {
    func removeInputAccessoryView() {
        guard let contentView = scrollView.subviews.first(where: {
            NSStringFromClass(type(of: $0)).hasPrefix("WKContentView")
        }) else { return }
        let baseClass: AnyClass = type(of: contentView)
        let name = NSStringFromClass(baseClass) + "_NoInputAccessory"
        if let existing = NSClassFromString(name) {
            object_setClass(contentView, existing)
            return
        }
        guard let subclass = objc_allocateClassPair(baseClass, name, 0),
              let method = class_getInstanceMethod(UIResponder.self, #selector(getter: UIResponder.inputAccessoryView))
        else { return }
        let block: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
        class_addMethod(
            subclass,
            #selector(getter: UIResponder.inputAccessoryView),
            imp_implementationWithBlock(block),
            method_getTypeEncoding(method)
        )
        objc_registerClassPair(subclass)
        object_setClass(contentView, subclass)
    }
}
