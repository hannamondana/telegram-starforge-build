import Foundation
import UIKit
import TelegramCore

func starForgeColor(_ rgb: UInt32, alpha: CGFloat = 1.0) -> UIColor {
    return UIColor(
        red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
        green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
        blue: CGFloat(rgb & 0xFF) / 255.0,
        alpha: alpha
    )
}

func starForgeFormattedInteger(_ value: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

func starForgeParseStars(_ text: String) -> Int64? {
    let cleaned = text.replacingOccurrences(of: " ", with: "")
    guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isNumber }) else {
        return nil
    }
    guard let value = Int64(cleaned) else {
        return nil
    }
    return min(max(0, value), 2_000_000_000)
}

struct StarForgeRecipient {
    let title: String
    let initials: String
    let colorSeed: Int

    init(title: String) {
        self.title = title

        var initials = ""
        for word in title.split(separator: " ").prefix(2) {
            if let character = word.first {
                initials.append(character)
            }
        }
        self.initials = initials.isEmpty ? "?" : initials.uppercased()

        var seed = 0
        for scalar in title.unicodeScalars {
            seed = seed &* 31 &+ Int(scalar.value)
        }
        self.colorSeed = abs(seed)
    }
}

struct StarForgeGift {
    let title: String
    let modelName: String?
    let number: Int32?
    let innerColor: UIColor
    let outerColor: UIColor

    init(title: String, modelName: String?, number: Int32?, innerColor: UIColor, outerColor: UIColor) {
        self.title = title
        self.modelName = modelName
        self.number = number
        self.innerColor = innerColor
        self.outerColor = outerColor
    }

    init(uniqueGift: StarGift.UniqueGift) {
        var innerColor = starForgeColor(0x7AC8FF)
        var outerColor = starForgeColor(0x2A6CF6)
        var modelName: String?

        for attribute in uniqueGift.attributes {
            switch attribute {
            case let .model(name, _, _, _):
                modelName = name
            case let .backdrop(_, _, inner, outer, _, _, _):
                innerColor = starForgeColor(UInt32(bitPattern: inner))
                outerColor = starForgeColor(UInt32(bitPattern: outer))
            default:
                break
            }
        }

        self.init(
            title: uniqueGift.title,
            modelName: modelName,
            number: uniqueGift.number,
            innerColor: innerColor,
            outerColor: outerColor
        )
    }

    static let fallback = StarForgeGift(
        title: "Plush Pepe",
        modelName: "Plush Pepe",
        number: 1,
        innerColor: starForgeColor(0x9BE7FF),
        outerColor: starForgeColor(0x2A6CF6)
    )
}

final class StarForgeSession {
    static let shared = StarForgeSession()

    private(set) var realStars: Int64 = 0
    private(set) var hasRealStars = false

    var starsOverride: Int64? {
        return StarForgeBalanceOverride.shared.stars
    }

    private init() {
    }

    func updateRealStars(_ value: Int64) {
        self.realStars = max(0, value)
        self.hasRealStars = true
    }

    func apply(stars: Int64?) {
        StarForgeBalanceOverride.shared.stars = stars
    }

    func reset() {
        StarForgeBalanceOverride.shared.reset()
    }
}
