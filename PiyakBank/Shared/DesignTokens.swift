import SwiftUI

enum PB {
    enum C {
        static let bg = adaptive(0xF6F4ED, 0x20212D)
        static let surface = adaptive(0xFFFFFF, 0x303140)
        static let textBrown = adaptive(0x34354C, 0xF4F0E6)
        static let secondary = adaptive(0x737185, 0xBAB6CC)
        /// 브랜드 강조색. 이름과 달리 실제 값은 보라 계열이라 accent로 부른다.
        static let accent = adaptive(0x6653BE, 0xB9A8FF)
        static let brandYellow = Color(hex: 0xFFDB63)
        static let mint = Color(hex: 0xC4EACF)
        static let lilac = Color(hex: 0xE4DCF7)
        static let ink = Color(hex: 0x34354C)
        static let outline = Color(hex: 0xE7BF57)
        static let eye = ink
        static let beak = Color(hex: 0xF5A05B)
        static let cheek = Color(hex: 0xF3A193)
        static let hoodieMint = Color(hex: 0x72D5B8)
        private static func adaptive(_ light: UInt, _ dark: UInt) -> Color {
            #if os(iOS)
            Color(uiColor: UIColor { traits in
                let hex = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                    green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
            })
            #else
            Color(hex: light)
            #endif
        }
    }
    enum R {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
        static let xl: CGFloat = 30
        static let pill: CGFloat = 999
    }
    enum F {
        static func amount(_ size: CGFloat) -> Font {
            .system(size >= 30 ? .largeTitle : .title3, design: .rounded, weight: .heavy)
        }
        static func body(_ size: CGFloat) -> Font {
            .system(size <= 12 ? .caption : size <= 14 ? .footnote : size <= 16 ? .subheadline : .body, design: .rounded)
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: alpha)
    }
}
