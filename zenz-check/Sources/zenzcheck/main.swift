import Foundation
import KanaKanjiConverterModule
import KanaKanjiConverterModuleWithDefaultDictionary

// Usage: zenzcheck <model.gguf>
let modelPath = CommandLine.arguments[1]
let dataDir = URL(fileURLWithPath: "/tmp/zenzcheck-data")
try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

func makeOptions(limit: Int) -> ConvertRequestOptions {
    ConvertRequestOptions(
        N_best: 10,
        requireJapanesePrediction: .disabled,
        requireEnglishPrediction: .disabled,
        keyboardLanguage: .ja_JP,
        englishCandidateInRoman2KanaInput: true,
        fullWidthRomanCandidate: false,
        halfWidthKanaCandidate: false,
        learningType: .inputAndOutput,
        maxMemoryCount: 65536,
        shouldResetMemory: false,
        memoryDirectoryURL: dataDir,
        sharedContainerURL: dataDir,
        textReplacer: .withDefaultEmojiDictionary(),
        specialCandidateProviders: nil,
        zenzaiMode: .on(weight: URL(fileURLWithPath: modelPath),
                        inferenceLimit: limit, personalizationMode: nil,
                        versionDependentMode: .v3(.init())),
        metadata: .init(versionString: "zenzcheck")
    )
}

let converter = KanaKanjiConverter.withDefaultDictionary()
let inputs = ["となりのきゃくはよくかきくうきゃくだ",
              "かきくうきゃくだ",
              "かき",
              "とうきょうとっきょきょかきょくきょくちょう"]
for limit in [1, 2, 3] {
    print("----- inferenceLimit \(limit) -----")
    let options = makeOptions(limit: limit)
    for input in inputs {
        var ct = ComposingText()
        ct.insertAtCursorPosition(input, inputStyle: .direct)
        let r = converter.requestCandidates(ct, options: options)
        print("[\(input)] -> \(r.mainResults.prefix(8).map { $0.text })")
    }
}
print("DONE")
