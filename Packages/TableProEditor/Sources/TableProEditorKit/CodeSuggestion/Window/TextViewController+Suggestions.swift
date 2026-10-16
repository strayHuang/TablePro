//
//  TextViewController+Suggestions.swift
//  TableProEditorKit
//

import AppKit

public extension TextViewController {
    /// Whether the completion popup is currently showing for this controller.
    var isShowingCompletions: Bool {
        SuggestionController.shared.model.isPresented && SuggestionController.shared.model.activeTextView === self
    }

    /// Ends this controller's completion session and reports whether a popup was on screen to
    /// dismiss.
    ///
    /// The two are separate answers on purpose. Escape and the Ctrl+Space toggle both read the
    /// return value to decide between dismissing and opening, so a session that never got a
    /// window must report `false` and still be ended: gating the close on visibility left the
    /// only two keys that could clear it doing nothing at all.
    @discardableResult
    func dismissCompletions() -> Bool {
        let controller = SuggestionController.shared
        guard controller.model.activeTextView === self else { return false }
        let wasShowing = controller.model.isPresented
        controller.close()
        return wasShowing
    }

    /// Opens the completion list at the caret without a manual-trigger flag, so the answer is the
    /// one the position itself earns.
    ///
    /// The caller is whoever edited the text and knows the caret landed somewhere worth listing —
    /// a snippet's stop is the case that needed it. It is deliberately not Escape or Ctrl-Space:
    /// those two ask for everything the position can offer, while this asks for what the position
    /// offers on its own, and the trigger policy still gets to shut a list it would shut for a
    /// keystroke. A window clause is where the difference shows: `… OVER (PARTITION BY ` lists the
    /// clauses that belong inside the parentheses, and it does so only because the policy exempts
    /// that clause from the empty-prefix rule.
    func requestCompletions() {
        guard let completionDelegate, let cursorPosition = cursorPositions.first else { return }
        SuggestionController.shared.showCompletions(
            textView: self,
            delegate: completionDelegate,
            cursorPosition: cursorPosition
        )
    }
}
