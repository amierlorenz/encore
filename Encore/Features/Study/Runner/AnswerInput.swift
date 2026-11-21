import EncoreKit

/// What the learner entered before revealing the answer.
struct AnswerInput {
    var text = ""
    var time = ""
    var space = ""
    var selectedOption: Int?

    func textRepresentation(for content: PromptContent?) -> String {
        if !text.isEmpty {
            if !time.isEmpty || !space.isEmpty {
                return "\(text) (\([time, space].filter { !$0.isEmpty }.joined(separator: ", ")))"
            }
            return text
        }
        if let selected = selectedOption, let options = content?.options, options.indices.contains(selected) {
            return options[selected]
        }
        if !time.isEmpty || !space.isEmpty {
            return [time, space].filter { !$0.isEmpty }.joined(separator: " / ")
        }
        return ""
    }
}
