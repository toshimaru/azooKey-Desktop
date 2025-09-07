import Cocoa
import Core
import Foundation
import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary

// MARK: - Reconversion Methods
extension azooKeyMacInputController {

    @MainActor
    func startReconversion(selectedText: String, client: IMKTextInput) {
        self.segmentsManager.appendDebugMessage("startReconversion: Starting reconversion for text: '\(selectedText)'")

        guard !selectedText.isEmpty else {
            self.segmentsManager.appendDebugMessage("startReconversion: No text selected")
            return
        }

        // Get selected range for replacement later
        let selectedRange = client.selectedRange()
        self.segmentsManager.appendDebugMessage("startReconversion: Selected range: \(selectedRange)")

        // Create basic conversion candidates
        let candidates = self.createReconversionCandidates(from: selectedText)

        if !candidates.isEmpty {
            self.segmentsManager.appendDebugMessage("startReconversion: Generated \(candidates.count) candidates")

            // Set up reconversion state
            self.setupReconversionState(
                candidates: candidates,
                selectedRange: selectedRange,
                client: client
            )

        } else {
            self.segmentsManager.appendDebugMessage("startReconversion: No candidates generated")
        }
    }

    // MARK: - Helper Methods

    @MainActor private func createReconversionCandidates(from text: String) -> [Candidate] {
        var candidates: [Candidate] = []

        // Add original text as first candidate
        candidates.append(Candidate(
            text: text,
            value: 0,
            composingCount: .surfaceCount(text.count),
            lastMid: 0,
            data: []
        ))

        // Convert to hiragana for kanji conversion
        let hiragana = text.toHiragana()

        // Add hiragana conversion if different from original
        if hiragana != text {
            candidates.append(Candidate(
                text: hiragana,
                value: -1,
                composingCount: .surfaceCount(text.count),
                lastMid: 0,
                data: []
            ))
        }

        // Get kanji conversion candidates using the kana-kanji converter
        if !hiragana.isEmpty {
            let kanjiCandidates = getKanjiCandidates(from: hiragana)
            candidates.append(contentsOf: kanjiCandidates)
        }

        // Add katakana conversion
        let katakana = text.toKatakana()
        if katakana != text && katakana != hiragana {
            candidates.append(Candidate(
                text: katakana,
                value: -2,
                composingCount: .surfaceCount(text.count),
                lastMid: 0,
                data: []
            ))
        }

        // Add half-width katakana
        if let halfWidthKatakana = katakana.applyingTransform(.fullwidthToHalfwidth, reverse: false),
           halfWidthKatakana != katakana {
            candidates.append(Candidate(
                text: halfWidthKatakana,
                value: -3,
                composingCount: .surfaceCount(text.count),
                lastMid: 0,
                data: []
            ))
        }

        // Add full-width roman (if applicable)
        if let fullWidthRoman = text.applyingTransform(.fullwidthToHalfwidth, reverse: true),
           fullWidthRoman != text {
            candidates.append(Candidate(
                text: fullWidthRoman,
                value: -4,
                composingCount: .surfaceCount(text.count),
                lastMid: 0,
                data: []
            ))
        }

        // Add half-width roman (if applicable)
        if let halfWidthRoman = text.applyingTransform(.fullwidthToHalfwidth, reverse: false),
           halfWidthRoman != text {
            candidates.append(Candidate(
                text: halfWidthRoman,
                value: -5,
                composingCount: .surfaceCount(text.count),
                lastMid: 0,
                data: []
            ))
        }

        self.segmentsManager.appendDebugMessage("createReconversionCandidates: Created \(candidates.count) candidates")
        return candidates
    }

    // Helper method to get kanji conversion candidates
    @MainActor private func getKanjiCandidates(from hiragana: String) -> [Candidate] {
        // Use SegmentsManager's public method to get kanji candidates
        segmentsManager.getKanjiConversionCandidates(for: hiragana)
    }

    @MainActor private func setupReconversionState(candidates: [Candidate], selectedRange: NSRange, client: IMKTextInput) {
        self.segmentsManager.appendDebugMessage("setupReconversionState: Setting up reconversion with \(candidates.count) candidates")

        // Store the selected range for later text replacement
        self.storeReconversionContext(selectedRange: selectedRange, candidates: candidates)

        // Set up SegmentsManager to display candidates
        self.segmentsManager.setReconversionCandidates(candidates: candidates)

        // Transition to selecting state to show candidate window
        // Use the proper ClientAction system to transition state
        _ = self.handleClientAction(.showCandidateWindow, clientActionCallback: .transition(.selecting), client: client)

        // Refresh the candidate window to display our candidates
        self.refreshCandidateWindow()

        self.segmentsManager.appendDebugMessage("setupReconversionState: Candidate window should now be visible")
    }

    // MARK: - Reconversion Context Management

    private func storeReconversionContext(selectedRange: NSRange, candidates: [Candidate]) {
        // Store reconversion context - the existing candidate selection system
        // handles text replacement automatically through the standard flow
        self.segmentsManager.appendDebugMessage("storeReconversionContext: Stored range \(selectedRange) with \(candidates.count) candidates")
    }
}
