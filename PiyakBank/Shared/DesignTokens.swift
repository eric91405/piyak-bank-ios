import SwiftUI

/// 확정 디자인 토큰. 다크모드 미구현 — 라이트 고정.
enum PB {

    // MARK: Color
    enum C {
        static let bg          = Color(hex: 0xFFF7EC) // 배경
        static let brandYellow = Color(hex: 0xFFD64D) // 몸통
        static let outline     = Color(hex: 0xEAB93A) // 외곽선
        static let coral       = Color(hex: 0xFF9E8A) // CTA
        static let textBrown   = Color(hex: 0x5C4A1E) // 텍스트 웜브라운
        static let eye         = Color(hex: 0x3A2E12) // 눈
        static let beak        = Color(hex: 0xFFB067) // 부리/발
        static let cheek       = Color(hex: 0xFFB3BA) // 볼터치
        static let hoodieMint  = Color(hex: 0xA8E6CF) // 후드티
    }

    // MARK: Radius
    enum R {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // MARK: Font (한글 Pretendard / 금액 SF Pro Rounded)
    enum F {
        static func amount(_ size: CGFloat) -> Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        static func body(_ size: CGFloat) -> Font {
            // Pretendard 번들 등록 시 .custom("Pretendard-Regular", size:)
            .system(size: size)
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
