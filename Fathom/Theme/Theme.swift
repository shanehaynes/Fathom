import SwiftUI

// §5 palette — the only UI colors in the app. The water owns everything else.
enum Theme {
    /// Every selected/active control. The only UI accent, ever (principle 3).
    static let warm = Color(red: 0xF2 / 255, green: 0xE8 / 255, blue: 0xD5 / 255)
    static let warmDim = warm.opacity(0.55)
    /// Ground.
    static let ink = Color(red: 0x06 / 255, green: 0x09 / 255, blue: 0x0E / 255)
    /// Cards/surfaces.
    static let ink2 = Color(red: 0x0A / 255, green: 0x0F / 255, blue: 0x16 / 255)
    static let textHi = Color(red: 0xD8 / 255, green: 0xE2 / 255, blue: 0xEC / 255)
    static let textMid = Color(red: 0x7E / 255, green: 0x8E / 255, blue: 0xA0 / 255)
    static let textLow = Color(red: 0x4A / 255, green: 0x57 / 255, blue: 0x68 / 255)
    static let line = Color(red: 140 / 255, green: 170 / 255, blue: 200 / 255).opacity(0.14)

    /// Translucent ink for control cards floating on the bright day scene (§4).
    static let cardInk = Color(red: 0x06 / 255, green: 0x09 / 255, blue: 0x0E / 255).opacity(0.55)
    /// Dark text on the warm "I'm up" button.
    static let onWarm = Color(red: 0x26 / 255, green: 0x22 / 255, blue: 0x1A / 255)
}

extension Font {
    /// Thin clock numerals with monospaced digits (§5 type).
    static func clock(_ size: CGFloat) -> Font {
        .system(size: size, weight: .ultraLight).monospacedDigit()
    }
    /// Small uppercase letterspaced labels.
    static let tag = Font.system(size: 11, weight: .regular)
}

extension View {
    func tagStyle(_ color: Color = Theme.textLow) -> some View {
        self.font(.tag)
            .textCase(.uppercase)
            .kerning(2.0)
            .foregroundStyle(color)
    }
}

// 24-hour clock for every numeral display, so 05:13 and 17:13 can never be confused.
enum Clock {
    static let hhmm = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: .current, calendar: .current
    )
}
