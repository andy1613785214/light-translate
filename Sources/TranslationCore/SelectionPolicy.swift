import Foundation

public enum SelectionResolution: Equatable {
    case text(String), emptyEditableSelection, copyRequired, protectedInput
}

public enum SelectionPolicy {
    /// A browser's focused web area can report empty text while its document still has a selection.
    /// An empty editable field is authoritative; copying there could select unrelated content.
    public static func resolve(selectedText: String?, isEditable: Bool, isProtected: Bool) -> SelectionResolution {
        if isProtected { return .protectedInput }
        guard let selectedText else { return .copyRequired }
        if !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .text(selectedText) }
        return isEditable ? .emptyEditableSelection : .copyRequired
    }
}
