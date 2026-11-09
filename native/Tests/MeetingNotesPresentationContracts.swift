import Foundation

@main enum MeetingNotesPresentationContracts {
    static func main() {
        let source = """
        # Meeting notes
        ## Overview
        Project moves to beta in June.

        ## Key points
        - **Design** is approved.
        - Testing needs one more pass.

        ## Decisions
        - Ship locally.

        ## Action items
        - [ ] Alex: prepare the build.
        - [x] Bea: confirm the scope.

        ## Open questions
        - Who owns the launch email?
        """
        let presentation = MeetingNotesPresentation(source)
        precondition(presentation.sections.map(\.title) ==
                     ["Overview", "Key points", "Decisions", "Action items", "Open questions"])
        precondition(presentation.sections.map(\.symbol) ==
                     ["text.alignleft", "list.bullet", "checkmark.seal", "checklist", "questionmark.circle"])
        precondition(presentation.sections[3].blocks.count == 2)
        if case .bullet(let item, let checked) = presentation.sections[3].blocks[0] {
            precondition(item == "Alex: prepare the build." && checked == false)
        } else { fatalError("unchecked action not parsed") }
        if case .bullet(_, let checked) = presentation.sections[3].blocks[1] {
            precondition(checked == true)
        } else { fatalError("checked action not parsed") }
        precondition(MeetingNotesPresentation("Old plain notes without headings").sections.count == 1)
        precondition(MeetingNotesPresentation("## Overview\nOnly present section").sections.map(\.title) == ["Overview"])
        precondition(MeetingNotesPresentation("# Overview\n\n## Decisions\nWe decided.").sections.map(\.title) == ["Decisions"])
        precondition(!MeetingNotesPresentation.hasNotes("  \n  "))
        precondition(MeetingNotesPresentation.shareText(title: "T", date: "Today", generatedNotes: " \n ") == nil)

        let shared = MeetingNotesPresentation.shareText(title: "Launch", date: "June 1", generatedNotes: source,
                                                        privateNotes: "PRIVATE DRAFT", markdown: true)!
        precondition(shared.hasPrefix("# Launch\n\nJune 1\n\n"))
        precondition(!shared.contains("PRIVATE DRAFT"))
        let optedIn = MeetingNotesPresentation.shareText(title: "Launch", date: "June 1", generatedNotes: source,
                                                         privateNotes: "PRIVATE DRAFT", includePrivateNotes: true)!
        precondition(optedIn.contains("## My notes\n\nPRIVATE DRAFT"))
        let plain = MeetingNotesPresentation.shareText(title: "Launch", date: "June 1", generatedNotes: source,
                                                       markdown: false)!
        precondition(plain.contains("Overview\nProject moves"))
        precondition(!plain.contains("## Overview"))
        precondition(MeetingNotesPresentation.safeFilename("../../Secret/Call:\n*notes? ") == "Secret Call notes")
        print("Meeting notes presentation contracts passed")
    }
}
