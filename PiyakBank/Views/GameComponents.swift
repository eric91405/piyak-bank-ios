import SwiftUI

struct GameButtonStyle: ButtonStyle {
    var color: Color = PB.C.brandYellow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle(PB.C.ink)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(color, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black.opacity(0.06), lineWidth: 1))
            .shadow(color: color.opacity(0.5), radius: 0, y: configuration.isPressed ? 0 : 4)
            .offset(y: configuration.isPressed ? 3 : 0)
            .opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BigButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    var body: some View { Button(title, action: action).buttonStyle(GameButtonStyle(color: color)) }
}

struct PointBadge: View {
    let amount: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "p.circle.fill").foregroundStyle(PB.C.ink)
            Text(amount.points).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
        }
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .foregroundStyle(PB.C.ink).padding(.horizontal, 12).padding(.vertical, 9)
        .background(PB.C.brandYellow, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("사용 가능한 포인트 \(amount.points)")
    }
}

struct GameCard: ViewModifier {
    var color: Color = PB.C.surface
    func body(content: Content) -> some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: PB.R.xl))
            .overlay(RoundedRectangle(cornerRadius: PB.R.xl).strokeBorder(PB.C.textBrown.opacity(0.04)))
    }
}
extension View {
    func gameCard(_ color: Color = PB.C.surface) -> some View { modifier(GameCard(color: color)) }
}

extension DecorSlot {
    var title: String {
        switch self {
        case .bg: "방 테마"
        case .wallDeco: "벽 장식"
        case .bigFurniture: "가구"
        case .floorProp: "소품"
        case .rug: "러그"
        case .bodyFront: "옷"
        case .headTop: "모자"
        case .eyes: "안경"
        case .headband: "머리띠"
        case .neck: "목 장식"
        }
    }
    var symbol: String {
        switch self {
        case .bg: "house.fill"
        case .wallDeco: "photo.artframe"
        case .bigFurniture: "sofa.fill"
        case .floorProp: "leaf.fill"
        case .rug: "square.stack.3d.down.right.fill"
        case .bodyFront: "tshirt.fill"
        case .headTop: "crown.fill"
        case .eyes: "eyeglasses"
        case .headband: "sparkles"
        case .neck: "heart.fill"
        }
    }
}
