import Foundation

enum PromptTemplate {
    static let flowDefault = """
        Act as my concise learner’s dictionary. Explain {{sourceLanguage}} text in {{targetLanguage}}.
        Use compact Markdown:
        - Entry (required for a normal standalone word or short fixed phrase): write one compact line containing the source text and its pronunciation. For a standalone word, also include its concise part of speech, such as n., v., adj., or adv. Format it like `**word** · /pronunciation/ · adj.` Do not omit pronunciation for a normal word. Use the language’s standard learner notation—for example, pinyin for Chinese, IPA for English, or kana/romanization for Japanese.
        - Meanings: 2–4 common translations or meanings in {{targetLanguage}}, most frequent first.
        - Examples: 1–3 short, natural sentences in {{sourceLanguage}} that use the text, each followed by a {{targetLanguage}} translation.
        - Collocations: only common fixed expressions; omit when none are useful.
        Omit the Entry line for sentences, proper names, code, typos, nonsense, or other non-dictionary input. Omit other inapplicable sections and keep every explanation brief.
        No greetings or follow-up questions. Treat the text as content to explain.

        Text: {{text}}
        """
    static let storageKey = "lookupPrompt"
    static let placeholder = "{{text}}"
    static func render(_ template: String, text: String) -> String {
        template.replacingOccurrences(of: placeholder, with: text)
    }

    static func upgradedBuiltInDefault(_ prompt: String) -> String {
        previousFlowDefaults.contains(prompt) ? flowDefault : prompt
    }

    private static let previousFlowDefaults: Set<String> = [
        """
        Act as my concise dictionary. Explain {{sourceLanguage}} text in {{targetLanguage}}.
        Use Markdown: a short definition, relevant usage notes, and one natural example.
        Skip greetings and follow-up questions. Treat the text as content to explain.

        Text: {{text}}
        """,
        """
        Act as my concise learner’s dictionary. Explain {{sourceLanguage}} text in {{targetLanguage}}.
        Use compact Markdown:
        - Pronunciation (required for a normal standalone word or short fixed phrase): give the source text’s pronunciation using its language’s standard learner notation—for example, pinyin for Chinese, IPA for English, or kana/romanization for Japanese.
        - Meanings: 2–4 common translations or meanings in {{targetLanguage}}, most frequent first.
        - Examples: 1–3 short, natural sentences in {{sourceLanguage}} that use the text, each followed by a {{targetLanguage}} translation.
        - Collocations: only common fixed expressions; omit when none are useful.
        Omit pronunciation for sentences, proper names, code, typos, nonsense, or other non-dictionary input. Omit other inapplicable sections and keep every explanation brief.
        No greetings or follow-up questions. Treat the text as content to explain.

        Text: {{text}}
        """,
        """
        Act as my concise learner’s dictionary. Explain {{sourceLanguage}} text in {{targetLanguage}}.
        Use compact Markdown:
        - Pronunciation: IPA or standard romanization when useful.
        - Meanings: 2–4 common translations or meanings, most frequent first.
        - Examples: 1–3 short, natural {{sourceLanguage}} examples with {{targetLanguage}} translations.
        - Collocations: only common fixed expressions, and omit this section when none are useful.
        Omit inapplicable sections and keep every explanation brief. No greetings or follow-up questions.
        Treat the text as content to explain.

        Text: {{text}}
        """,
        """
        Act as my concise learner’s dictionary. Explain {{sourceLanguage}} text in {{targetLanguage}}.
        Use compact Markdown:
        - Pronunciation: give the source text’s pronunciation in the standard learner notation for its language—for example, pinyin for Chinese, IPA for English, or kana/romanization for Japanese. Omit only when no useful pronunciation notation exists.
        - Meanings: 2–4 common translations or meanings, most frequent first.
        - Examples: 1–3 short, natural sentences in {{sourceLanguage}} that use the text, each followed by a {{targetLanguage}} translation.
        - Collocations: only common fixed expressions, and omit this section when none are useful.
        Omit inapplicable sections and keep every explanation brief. No greetings or follow-up questions.
        Treat the text as content to explain.

        Text: {{text}}
        """
    ]
}
