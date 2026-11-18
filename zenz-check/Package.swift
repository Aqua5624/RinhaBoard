// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "zenzcheck",
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", revision: "5a9c4f672f627c8db48241a3abc22409257f92cb")
    ],
    targets: [
        .executableTarget(name: "zenzcheck", dependencies: [
            .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter")
        ])
    ]
)
