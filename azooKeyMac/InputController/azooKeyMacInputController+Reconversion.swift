import Cocoa
import Core
import Foundation
import InputMethodKit
import KanaKanjiConverterModuleWithDefaultDictionary

// MARK: - Reconversion Methods
extension azooKeyMacInputController {
    @MainActor
    func startReconversion(selectedText: String) {
        self.segmentsManager.appendDebugMessage("startReconversion: Starting reconversion for text: '\(selectedText)'")

        guard !selectedText.isEmpty else {
            self.segmentsManager.appendDebugMessage("startReconversion: No text selected")
            return
        }

        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("startReconversion: No client available")
            return
        }

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

        // Add kanji-to-hiragana reverse conversion using system API
        let kanjiReadings = getReadingFromSystemAPI(for: text)
        for reading in kanjiReadings {
            if reading != text && reading != hiragana {
                candidates.append(Candidate(
                    text: reading,
                    value: -10, // Lower priority than direct conversions
                    composingCount: .surfaceCount(text.count),
                    lastMid: 0,
                    data: []
                ))
            }
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

    @MainActor private func getKanjiCandidates(from hiragana: String) -> [Candidate] {
        // Use SegmentsManager's public method to get kanji candidates
        segmentsManager.getKanjiConversionCandidates(for: hiragana)
    }

    // Get hiragana reading from kanji using system API (CFStringTokenizer)
    private func getReadingFromSystemAPI(for text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }

        let containsKanji = text.contains { char in
            let unicodeValue = char.unicodeScalars.first?.value ?? 0
            return unicodeValue >= 0x4E00 && unicodeValue <= 0x9FFF
        }
        guard containsKanji else {
            return []
        }

        let inputText = text as NSString
        let outputText = NSMutableString()
        var range: CFRange = CFRangeMake(0, inputText.length)

        // Create tokenizer
        let tokenizer: CFStringTokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            inputText as CFString,
            range,
            kCFStringTokenizerUnitWordBoundary,
            CFLocaleCopyCurrent()
        )

        var tokenType: CFStringTokenizerTokenType = CFStringTokenizerGoToTokenAtIndex(tokenizer, 0)
        while tokenType.rawValue != 0 {
            range = CFStringTokenizerGetCurrentTokenRange(tokenizer)

            // Get latin transcription (romaji)
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) {
                guard let romaji = latin as? NSString else {
                    continue
                }

                // Convert to hiragana
                guard let furigana = romaji.mutableCopy() as? NSMutableString else {
                    continue
                }
                let success = CFStringTransform(furigana as CFMutableString, nil, kCFStringTransformLatinHiragana, false)

                if success {
                    outputText.append(furigana as String)
                } else {
                    // Fallback: append original text if conversion fails
                    let substring = inputText.substring(with: NSRange(location: range.location, length: range.length))
                    outputText.append(substring)
                }
            } else {
                // No latin transcription available, append original text
                let substring = inputText.substring(with: NSRange(location: range.location, length: range.length))
                outputText.append(substring)
            }

            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        let result = outputText as String

        // Return array with the reading if different from original
        if result != text && !result.isEmpty {
            self.segmentsManager.appendDebugMessage("getReadingFromSystemAPI: '\(text)' -> '\(result)'")
            return [result]
        }

        return []
    }

    @MainActor private func setupReconversionState(candidates: [Candidate], selectedRange: NSRange, client: IMKTextInput) {
        self.segmentsManager.appendDebugMessage("setupReconversionState: Setting up reconversion with \(candidates.count) candidates")

        // Set up SegmentsManager to display candidates
        self.segmentsManager.setReconversionCandidates(candidates: candidates)

        // Transition to selecting state to show candidate window
        // Use the proper ClientAction system to transition state
        _ = self.handleClientAction(.showCandidateWindow, clientActionCallback: .transition(.selecting), client: client)

        // Refresh the candidate window to display our candidates
        self.refreshCandidateWindow()

        self.segmentsManager.appendDebugMessage("setupReconversionState: Candidate window should now be visible")
    }
}
