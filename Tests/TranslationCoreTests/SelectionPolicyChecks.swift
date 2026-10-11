import TranslationCore

extension TranslationCoreTests {
    func testEmptyBrowserSelectionFallsBackButEmptyEditorDoesNot() {
        expectEqual(SelectionPolicy.resolve(selectedText: "", isEditable: false, isProtected: false), .copyRequired)
        expectEqual(SelectionPolicy.resolve(selectedText: " \n", isEditable: true, isProtected: false), .emptyEditableSelection)
        expectEqual(SelectionPolicy.resolve(selectedText: nil, isEditable: false, isProtected: false), .copyRequired)
        expectEqual(SelectionPolicy.resolve(selectedText: "selected sentence", isEditable: false, isProtected: false), .text("selected sentence"))
    }
    func testProtectedFieldsNeverUseCopyOrText() {
        expectEqual(SelectionPolicy.resolve(selectedText: "secret", isEditable: true, isProtected: true), .protectedInput)
        expectEqual(SelectionPolicy.resolve(selectedText: nil, isEditable: false, isProtected: true), .protectedInput)
    }
}
