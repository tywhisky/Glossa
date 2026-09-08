import Testing
@testable import Glossa

@Test func promptSubstitutionPreservesUserContent() {
    #expect(PromptTemplate.defaultValue.contains(PromptTemplate.placeholder))
    #expect(PromptTemplate.render("Define {{text}} / {{text}}", text: "你好\n**word**") == "Define 你好\n**word** / 你好\n**word**")
    #expect(PromptTemplate.render("{{text}}", text: "literal {{text}}") == "literal {{text}}")
    #expect(PromptTemplate.render("{{text}}", text: "") == "")
    #expect(PromptTemplate.render("Keep my instructions", text: "word") == "Keep my instructions")
}
