// swift-tools-version: 6.1
import PackageDescription

// AzooKeyKanaKanjiConverter は SwiftPM trait「ZenzaiCPU」を有効化しないと
// Zenzai の実体ではなく fatalError するモック実装でビルドされる。
// Xcode プロジェクトからは trait を指定できないため、このローカルパッケージを
// 経由して trait 付きで依存する（azooKey 本家の AzooKeyCore と同じ方式）。
let package = Package(
    name: "SparkleKeyCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SparkleKeyCore", targets: ["SparkleKeyCore"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
            revision: "5a9c4f672f627c8db48241a3abc22409257f92cb",
            traits: ["ZenzaiCPU"]
        )
    ],
    targets: [
        .target(
            name: "SparkleKeyCore",
            dependencies: [
                .product(
                    name: "KanaKanjiConverterModuleWithDefaultDictionary",
                    package: "AzooKeyKanaKanjiConverter"
                )
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        )
    ]
)
