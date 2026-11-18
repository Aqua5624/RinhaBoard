import Foundation

/// 絵文字パネルのデータ（カテゴリ別、空白区切り）
enum EmojiData {
    struct Category {
        let symbol: String   // タブ用 SF Symbol
        let fallback: String // シンボルが無い場合の表示
        let items: [String]
    }

    private static func split(_ s: String) -> [String] {
        s.split(separator: " ").map(String.init)
    }

    static let categories: [Category] = [
        Category(symbol: "face.smiling", fallback: "😀", items: split(
            "😀 😁 😂 🤣 😊 😍 😘 😎 🤩 🥳 😏 😌 😴 😪 🤤 😜 🤪 😝 🤑 🤗 🤔 🤨 😐 😑 😶 🙄 😬 😮 😲 😳 🥺 😢 😭 😱 😖 😣 😞 😟 😤 😡 🤯 🥵 🥶 😈 👿 💀 👻 👽 🤖 🎃 😺 😸 😹 😻 😼 😽 🙀 😿 😾")),
        Category(symbol: "hand.raised", fallback: "👍", items: split(
            "👍 👎 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👋 🤚 🖐 ✋ 🖖 👏 🙌 🤲 🙏 💪 👊 ✊ 🤛 🤜 👆 👇 👈 👉 ☝️ ✍️ 💅 🤳 👀 👁 👄 💋 🧠 🦴")),
        Category(symbol: "heart.fill", fallback: "❤️", items: split(
            "❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 ✨ ⭐ 🌟 💫 🔥 💯 💢 💥 💦 💨 🎵 🎶 🔔 🎉 🎊 🎁 🏆 🥇 🥈 🥉 💎 💰 💸 📱 💻 ⌚ 📷 🔑 🔒 🔓 ✏️ 📝 📚 📖 🔍 💡 🔦")),
        Category(symbol: "fork.knife", fallback: "🍔", items: split(
            "🍎 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍒 🍑 🥭 🍍 🥝 🍅 🥑 🥦 🌽 🥕 🧄 🥔 🍞 🥐 🧀 🥚 🍳 🥓 🍗 🍖 🌭 🍔 🍟 🍕 🍝 🍜 🍲 🍣 🍱 🍛 🍙 🍚 🍘 🍥 🍢 🍡 🍧 🍨 🍦 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🥛 ☕ 🍵 🧃 🍺 🍻 🥂 🍷 🥤")),
        Category(symbol: "pawprint.fill", fallback: "🐶", items: split(
            "🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐸 🐵 🙈 🙉 🙊 🐔 🐧 🐦 🐤 🦆 🦅 🦉 🐴 🦄 🐝 🦋 🐌 🐞 🐙 🦑 🦐 🐠 🐟 🐬 🐳 🐋 🦈 🌸 🌺 🌻 🌹 🌷 🌼 🌵 🌲 🌳 🍀 🍁 🍂 🍃 🌈 ☀️ 🌧 ❄️ ⛄")),
        Category(symbol: "car.fill", fallback: "🚗", items: split(
            "⚽ ⚾ 🏀 🏐 🏈 🎾 🎱 🏓 🏸 ⛳ 🎣 🛹 🎮 🎯 🎲 🎳 🚗 🚕 🚙 🚌 🏎 🚓 🚑 🚒 🚚 🚛 🛵 🏍 🚲 ✈️ 🚀 🛸 🚁 ⛵ 🚢 ⚓ 🏠 🏢 🏫 🏥 🏦 🏨 💒 🗼 🗽 ⛩ 🏯 🎡 🎢 🎠")),
    ]
}
