// swift-tools-version:6.1
import PackageDescription
let package = Package(
    name: "zenzcheck",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", revision: "5a9c4f672f627c8db48241a3abc22409257f92cb", traits: ["Zenzai"])
    ],
    targets: [
        .executableTarget(name: "zenzcheck", dependencies: [
            .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter")
        ])
    ]
)
