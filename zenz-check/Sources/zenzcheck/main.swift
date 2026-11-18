import Foundation
import KanaKanjiConverterModule
import KanaKanjiConverterModuleWithDefaultDictionary

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: zenzcheck <model.gguf>\n".data(using: .utf8)!)
    exit(2)
}
let weight = URL(fileURLWithPath: args[1])

func convert(_ kana: String, limit: Int, converter: KanaKanjiConverter) -> [String] {
    var text = ComposingText()
    text.insertAtCursorPosition(kana, inputStyle: .direct)
    let options = ConvertRequestOptions(
        requireJapanesePrediction: .disabled,
        requireEnglishPrediction: .disabled,
        keyboardLanguage: .ja_JP,
        typographyLetterCandidate: false,
        englishCandidateInRoman2KanaInput: true,
        fullWidthRomanCandidate: false,
        halfWidthKanaCandidate: false,
        learningType: .nothing,
        maxMemoryCount: 0,
        shouldResetMemory: false,
        memoryDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory()),
        sharedContainerURL: URL(fileURLWithPath: NSTemporaryDirectory()),
        textReplacer: .withDefaultEmojiDictionary(),
        specialCandidateProviders: nil,
        zenzaiMode: .on(weight: weight, inferenceLimit: limit,
                        personalizationMode: nil, versionDependentMode: .v3(.init())),
        metadata: .init(versionString: "zenzcheck")
    )
    return converter.requestCandidates(text, options: options)
        .prefix(8).map { $0.text }
}

let converter = KanaKanjiConverter()
let inputs = [
    "となりのきゃくはよくかきくうきゃくだ",
    "かきくうきゃくだ",
    "かき",
    "とうきょうとっきょきょかきょくきょくちょう",
]
for limit in [1, 2, 3] {
    print("----- inferenceLimit \(limit) -----")
    for input in inputs {
        let top = convert(input, limit: limit, converter: converter)
        print("[\(input)] -> \(top)")
    }
}
print("DONE")
