import Foundation

/// 絵文字パネルのデータ（カテゴリ別、空白区切り）
enum EmojiData {
    struct Category {
        let symbol: String   // タブ用 SF Symbol
        let fallback: String // シンボルが無い場合の表示
        let title: String    // セクション見出し
        var wide: Bool = false // 顔文字など横幅が要るもの
        let items: [String]
    }

    private static func split(_ s: String) -> [String] {
        s.split(separator: " ").map(String.init)
    }

    static let categories: [Category] = [
        Category(symbol: "face.smiling", fallback: "😀", title: "顔", items: split(
            "😀 😁 😂 🤣 😊 😍 😘 😎 🤩 🥳 😏 😌 😴 😪 🤤 😜 🤪 😝 🤑 🤗 🤔 🤨 😐 😑 😶 🙄 😬 😮 😲 😳 🥺 😢 😭 😱 😖 😣 😞 😟 😤 😡 🤯 🥵 🥶 😈 👿 💀 👻 👽 🤖 🎃 😺 😸 😹 😻 😼 😽 🙀 😿 😾")),
        Category(symbol: "hand.raised", fallback: "👍", title: "手・からだ", items: split(
            "👍 👎 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👋 🤚 🖐 ✋ 🖖 👏 🙌 🤲 🙏 💪 👊 ✊ 🤛 🤜 👆 👇 👈 👉 ☝️ ✍️ 💅 🤳 👀 👁 👄 💋 🧠 🦴")),
        Category(symbol: "heart.fill", fallback: "❤️", title: "ハート・記号", items: split(
            "❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 ✨ ⭐ 🌟 💫 🔥 💯 💢 💥 💦 💨 🎵 🎶 🔔 🎉 🎊 🎁 🏆 🥇 🥈 🥉 💎 💰 💸 📱 💻 ⌚ 📷 🔑 🔒 🔓 ✏️ 📝 📚 📖 🔍 💡 🔦")),
        Category(symbol: "fork.knife", fallback: "🍔", title: "食べ物", items: split(
            "🍎 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍒 🍑 🥭 🍍 🥝 🍅 🥑 🥦 🌽 🥕 🧄 🥔 🍞 🥐 🧀 🥚 🍳 🥓 🍗 🍖 🌭 🍔 🍟 🍕 🍝 🍜 🍲 🍣 🍱 🍛 🍙 🍚 🍘 🍥 🍢 🍡 🍧 🍨 🍦 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🥛 ☕ 🍵 🧃 🍺 🍻 🥂 🍷 🥤")),
        Category(symbol: "pawprint.fill", fallback: "🐶", title: "動物・自然", items: split(
            "🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🐴 🦄 🐝 🦋 🐌 🐞 🐙 🦑 🦐 🐠 🐟 🐬 🐳 🐋 🦈 🌸 🌺 🌻 🌹 🌷 🌼 🌵 🌲 🌳 🍀 🍁 🍂 🍃 🌈 ☀️ 🌧 ❄️ ⛄")),
        Category(symbol: "car.fill", fallback: "🚗", title: "乗り物・スポーツ", items: split(
            "⚽ ⚾ 🏀 🏐 🏈 🎾 🎱 🏓 🏸 ⛳ 🎣 🛹 🎮 🎯 🎲 🎳 🚗 🚕 🚙 🚌 🏎 🚓 🚑 🚒 🚚 🚛 🛵 🏍 🚲 ✈️ 🚀 🛸 🚁 ⛵ 🚢 ⚓ 🏠 🏢 🏫 🏥 🏦 🏨 💒 🗼 🗽 ⛩ 🏯 🎡 🎢 🎠")),
        Category(symbol: "", fallback: "(´∀｀)", title: "顔文字", wide: true, items: [
            "(´∀｀)", "(´▽｀)", "(≧▽≦)", "(´ω｀)", "(・∀・)", "(ﾟ∀ﾟ)",
            "(´∀｀*)", "(´ε｀)", "( ˘ω˘ )", "(´-ω-`)", "(=_=)", "(￣▽￣)",
            "(´_ゝ｀)", "(｀・ω・´)", "(´Д｀)", "(ﾟДﾟ)", "(；∀；)", "(T_T)",
            "(；ω；)", "(´；ω；｀)", "(ﾉД`)", "(≧Д≦)", "(T▽T)", "(´・ω・｀)",
            "(´・ω・`)", "(・ω・)", "(´・∀・｀)", "(´Д｀)ﾊｧ…", "(´ﾟдﾟ｀)", "( ﾟдﾟ )",
            "(´∀｀)ﾉｼ", "(´ω｀)ﾉｼ", "(ﾉ´∀｀*)ﾉ", "(´▽｀)ﾉ", "(ﾉД`)ｼｸｼｸ", "(´・ω・｀)ｼｮﾎﾞｰﾝ",
        ]),
    ]
}
