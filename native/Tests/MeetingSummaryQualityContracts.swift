import Foundation

@main enum MeetingSummaryQualityContracts {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func json(_ items: [[String: String]]) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: ["items": items]), encoding: .utf8)!
    }
    static func main() async throws {
        let source = "The cedar garden budget is 1700 dollars. We agreed to use the cedar irrigation plan. Maya will send the plan by January 13. Could we add another pump? We did not approve the proposed pump."
        let model = try json([
            ["section":"Overview", "text":"Cedar garden budget is 1700 dollars.", "evidence":"The cedar garden budget is 1700 dollars."],
            ["section":"Decisions", "text":"We agreed to use the cedar irrigation plan.", "evidence":"We agreed to use the cedar irrigation plan."],
            ["section":"Action items", "text":"Maya will send the plan by January 13.", "evidence":"Maya will send the plan by January 13."],
            ["section":"Open questions", "text":"Could we add another pump?", "evidence":"Could we add another pump?"],
            ["section":"Decisions", "text":"We approve the pump.", "evidence":"We did not approve the proposed pump."],
            ["section":"Key points", "text":"The transcript says the cedar garden budget is 1700 dollars.", "evidence":"The cedar garden budget is 1700 dollars."],
            ["section":"Action items", "text":"Alex will send the plan by January 14.", "evidence":"Maya will send the plan by January 13."]
        ])
        let result = try await MeetingSummarizer.generate(source, condense: { _ in model })
        check(result.notes.contains("## Overview") && result.notes.contains("## Decisions") && result.notes.contains("## Action items") && result.notes.contains("## Open questions"), "missing readable section organization")
        check(result.notes.contains("- [ ] Maya will send the plan by January 13."), "action lost explicit owner or deadline")
        check(!result.notes.contains("Alex") && !result.notes.contains("January 14") && !result.notes.contains("We approve") && !result.notes.lowercased().contains("transcript"), "unfounded model content escaped evidence validation")
        check(result.notes.contains("## Key points\n- We did not approve the proposed pump."), "rejected proposal disappeared from context")

        let repeated = "We agreed to use the cedar irrigation plan. We agreed to use the cedar irrigation plan."
        let fallback = try await MeetingSummarizer.generate(repeated, condense: { _ in "not valid JSON" })
        check(fallback.notes.components(separatedBy: "We agreed to use").count == 2, "duplicate decision not consolidated")
        check(!fallback.notes.contains("Overview"), "decision incorrectly promoted to overview")
        let natural = "We did not approve the proposed pump. Maybe we could review it next week."
        let uncertain = try await MeetingSummarizer.generate(natural, condense: { _ in "" })
        check(uncertain.notes.contains("not approve") && !uncertain.notes.contains("## Decisions") && !uncertain.notes.contains("## Action items"), "uncertainty became commitment")
        let greeting = try await MeetingSummarizer.generate("Thank you. Thank you. Bye. Okay. Yes. Take care. You too. ...", condense: { _ in "" })
        check(greeting.notes.isEmpty, "closing phrases became meeting notes")
        let swappedEvidence = "Maya will send the draft by Monday, and Alex will review the plan by Friday."
        let swappedModel = try json([["section":"Action items", "text":"Maya will send the plan by Friday.", "evidence":swappedEvidence]])
        let swapped = try await MeetingSummarizer.generate(swappedEvidence, condense: { _ in swappedModel })
        check(!swapped.notes.contains("Maya will send the plan by Friday"), "word-bag validator accepted a swapped owner/deadline relation")
        check(swapped.notes.contains(swappedEvidence), "failed relation validation lost the supported original")
        let misplacedNegation = "Maya will not send the draft, and Alex will send the plan by Friday."
        let negatedModel = try json([["section":"Key points", "text":"Alex will not send the plan by Friday.", "evidence":misplacedNegation]])
        let negated = try await MeetingSummarizer.generate(misplacedNegation, condense: { _ in negatedModel })
        check(!negated.notes.contains("Alex will not send"), "word-bag validator attached negation to the wrong person")
        let utterances = "[00:00:01] We did not approve the pump\n[00:00:02] We agreed to use cedar irrigation plan"
        let separate = try await MeetingSummarizer.generate(utterances, condense: { _ in "" })
        check(separate.notes.contains("## Decisions\n- We agreed to use cedar irrigation plan"), "newline collapse made previous negation swallow a decision")
        check(!separate.notes.contains("## Decisions\n- We did not approve"), "negated utterance became decision")
        let shortDecision = try await MeetingSummarizer.generate("We approved launch.", condense: { _ in "" })
        check(shortDecision.notes.contains("## Decisions\n- We approved launch."), "short substantive decision dropped")
        let transcriptDecision = "We approved publishing the transcript on Friday."
        let transcriptionTask = "Maya will review the transcription by Monday."
        let topicSource = transcriptDecision + " " + transcriptionTask
        let topicModel = try json([
            ["section":"Decisions", "text":"The transcript says publishing was approved.", "evidence":transcriptDecision],
            ["section":"Action items", "text":"The transcription task belongs to Maya.", "evidence":transcriptionTask]
        ])
        let groundedTopics = MeetingSummarizer.validatedItems(topicModel, source: topicSource)
        check(groundedTopics.count == 2 && groundedTopics[0].text == transcriptDecision && groundedTopics[1].text == transcriptionTask,
              "actual transcript/transcription discussion rejected as source evidence or replaced with model narration")
        let topicFallback = try await MeetingSummarizer.generate(topicSource, condense: { _ in "" })
        check(topicFallback.notes.contains(transcriptDecision) && topicFallback.notes.contains(transcriptionTask),
              "extractive fallback dropped actual transcript/transcription discussion")
        let fiveFacts = (1...5).map { "The garden detail \($0) remains important." }.joined(separator: "\n")
        let allFacts = try await MeetingSummarizer.generate(fiveFacts, condense: { _ in "" })
        check(allFacts.notes.contains("The garden detail 5 remains important."), "fifth relevant context fact silently capped")
        let oversized = String(repeating: "context ", count: 373) + "Maya will send the draft by Monday " + String(repeating: "context ", count: 40)
        let overlapping = MeetingSummarizer.windows(oversized)
        check(overlapping.count > 1 && overlapping.contains(where: { $0.contains("Maya will send the draft by Monday") }), "oversized utterance cut a commitment across windows")
        let boundaryNotes = try await MeetingSummarizer.generate(oversized, condense: { _ in "" })
        check(boundaryNotes.notes.contains("Maya will send the draft by Monday"), "split-window commitment vanished from notes")

        let long = (0..<6).map { "The cedar garden discussion item \($0) includes " + String(repeating: "watering detail ", count: 110) + "." }.joined(separator: "\n") + "\nLena will deliver the final review by Friday."
        var windows: [String] = []
        let complete = try await MeetingSummarizer.generate(long, condense: { chunk in windows.append(chunk); return "" })
        check(windows.count > 2 && windows.joined(separator: " ").contains("Lena will deliver"), "tail omitted from model coverage")
        check(complete.notes.contains("Lena will deliver the final review by Friday."), "late follow-up omitted from minutes")
        check(complete.notes.contains("discussion item 0") && complete.notes.contains("discussion item 5"), "global organization lost distinct topics")
        let facts = try await MeetingSummarizer.generate("There will be 1700 admins affected. Have we agreed to the launch? No decision is final. Maya will not send the draft.", condense: { _ in "" })
        check(!facts.notes.contains("## Decisions") && !facts.notes.contains("## Action items") && facts.notes.contains("## Open questions"), "factual future, negation or question became commitment")
        let omittedModel = try json([["section":"Overview", "text":"The cedar garden budget is 1700 dollars.", "evidence":"The cedar garden budget is 1700 dollars."]])
        let covered = try await MeetingSummarizer.generate(source, condense: { _ in omittedModel })
        check(covered.notes.contains("Maya will send") && covered.notes.contains("not approve"), "valid but incomplete model dropped commitments or rejected proposal")
        let misplacedModel = try json([["section":"Key points", "text":"Maya will send the plan by January 13.", "evidence":"Maya will send the plan by January 13."]])
        let corrected = try await MeetingSummarizer.generate(source, condense: { _ in misplacedModel })
        check(corrected.notes.contains("- [ ] Maya will send"), "model misclassification hid explicit task")
        let decimal = try await MeetingSummarizer.generate("The garden cost is 12.75 dollars and the team will review it on Friday.", condense: { _ in "" })
        check(decimal.notes.contains("12.75"), "sentence splitting damaged decimal")
        do {
            _ = try await MeetingSummarizer.generate(source, condense: { _ in throw CancellationError() })
            fatalError("cancellation swallowed")
        } catch is CancellationError { }
        let cancelled = Task {
            try await MeetingSummarizer.generate(source, condense: { _ in
                withUnsafeCurrentTask { $0?.cancel() }; return model
            })
        }
        do { _ = try await cancelled.value; fatalError("normally returning cancellation committed") }
        catch is CancellationError { }
        print("PASS: grounded sections, rejected inventions/meta-language, uncertainty, deduplication, full-window/tail coverage, decimals, cancellation")
    }
}
