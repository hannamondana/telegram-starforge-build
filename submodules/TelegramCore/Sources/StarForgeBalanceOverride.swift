import Foundation

/// Session-local, display-only override for the user's star balance.
///
/// The value is read by balance UI components and never reaches engine, payment
/// or network code. Setting it changes what the app draws, not what the account
/// actually owns.
public final class StarForgeBalanceOverride {
    public static let shared = StarForgeBalanceOverride()

    /// Star balance override, in whole stars.
    public var stars: Int64?

    private init() {
    }

    public var isActive: Bool {
        return self.stars != nil
    }

    public func reset() {
        self.stars = nil
    }

    /// Returns the overridden star amount, or the original amount.
    public func overriddenStarsAmount(_ value: StarsAmount, ton: Bool) -> StarsAmount {
        if !ton, let stars = self.stars {
            return StarsAmount(value: stars, nanos: 0)
        }
        return value
    }
}
