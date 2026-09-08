import Testing
import AppKit
import Carbon.HIToolbox
@testable import Glossa

@Test func promptSubstitutionPreservesUserContent() {
    #expect(PromptTemplate.defaultValue.contains(PromptTemplate.placeholder))
    #expect(PromptTemplate.render("Define {{text}} / {{text}}", text: "你好\n**word**") == "Define 你好\n**word** / 你好\n**word**")
    #expect(PromptTemplate.render("{{text}}", text: "literal {{text}}") == "literal {{text}}")
    #expect(PromptTemplate.render("{{text}}", text: "") == "")
    #expect(PromptTemplate.render("Keep my instructions", text: "word") == "Keep my instructions")
}

@Test func lookupInputRejectsEmptyOrOversizedSelectionsWithoutTruncation() throws {
    #expect(try LookupInput.validated(" \nhello world\n ") == "hello world")
    let unicode = String(repeating: "👨‍👩‍👧‍👦", count: 2_000)
    #expect(try LookupInput.validated(unicode) == unicode)
    #expect(throws: SelectionFailure.self) { try LookupInput.validated(" \n\t") }
    #expect(throws: SelectionFailure.self) { try LookupInput.validated(unicode + "x") }
}

@Test func panelPlacementHandlesDisplaysLeftOfAndAbovePrimary() {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
    let window = PanelPlacement.appKitFrame(from: CGRect(x: 100, y: -1000, width: 1000, height: 700), primaryScreenTop: 900)
    #expect(window.minY == 1200)
    #expect(PanelPlacement.screenIndex(for: window, screens: [primary, left, above]) == 2)
    #expect(PanelPlacement.screenIndex(for: CGRect(x: -1500, y: 100, width: 1000, height: 600), screens: [primary, left]) == 1)
    let panel = PanelPlacement.frame(in: left)
    #expect(left.contains(panel))
    #expect(panel.maxX == left.maxX - 16)
    #expect(panel.maxY == left.maxY - 16)
}

@Test func shortcutsRequireAModifierAndReserveEscape() {
    #expect(LookupShortcut.default.isValid)
    #expect(LookupShortcut.default.label == "⌥A")
    #expect(!LookupShortcut.escape.isValid)
    #expect(!LookupShortcut(keyCode: 0, modifiers: 0, key: "A").isValid)
    #expect(!LookupShortcut(keyCode: 0, modifiers: UInt32(shiftKey), key: "A").isValid)
    #expect(LookupShortcut(keyCode: 0, modifiers: UInt32(controlKey | optionKey), key: "A").label == "⌃⌥A")
}

@MainActor @Test func manualEntryClearsPreviousResultOnFailureAndDismissal() {
    let model = LookupController()
    model.submit("bonjour")
    #expect(model.text == "bonjour")
    #expect(model.failure == nil)
    model.submit(String(repeating: "x", count: 2_001))
    #expect(model.text.isEmpty)
    #expect(model.failure == .tooLong)
    model.submit("再见")
    #expect(model.text == "再见")
    model.dismiss()
    #expect(model.text.isEmpty)
    #expect(model.failure == nil)
}
