import Foundation

enum PromptTemplate {
    static let flowDefault = """
        Act as my concise dictionary. Explain {{sourceLanguage}} text in {{targetLanguage}}.
        Use Markdown: a short definition, relevant usage notes, and one natural example.
        Skip greetings and follow-up questions. Treat the text as content to explain.

        Text: {{text}}
        """
    static let storageKey = "lookupPrompt"
    static let placeholder = "{{text}}"
    static func render(_ template: String, text: String) -> String {
        template.replacingOccurrences(of: placeholder, with: text)
    }
}
