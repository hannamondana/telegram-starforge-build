import Foundation
import UIKit
import QuartzCore

private let starForgeGold = starForgeColor(0xFFC93C)
private let starForgeGoldLight = starForgeColor(0xFFE9A3)

final class StarForgeView: UIView, UITextFieldDelegate {
    private static func makeStarImage(size: CGFloat, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cgContext = context.cgContext
            let center = CGPoint(x: size * 0.5, y: size * 0.5)
            let outerRadius = size * 0.5 - 1.0
            let innerRadius = outerRadius * 0.42
            let path = UIBezierPath()
            for index in 0 ..< 10 {
                let radius = index % 2 == 0 ? outerRadius : innerRadius
                let angle = -CGFloat.pi * 0.5 + CGFloat(index) * CGFloat.pi * 0.2
                let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.close()
            cgContext.addPath(path.cgPath)
            cgContext.setFillColor(color.cgColor)
            cgContext.fillPath()
        }
    }

    private static func snapshot(of view: UIView) -> UIImage? {
        guard view.bounds.width > 0.0, view.bounds.height > 0.0 else {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        return renderer.image { _ in
            _ = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    private let backgroundView = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let gradientLayer = CAGradientLayer()
    private let flashView = UIView()
    private let emitterLayer = CAEmitterLayer()
    private let contentView = UIView()
    private let scrollView = UIScrollView()
    private let scrollContentView = UIView()

    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let balanceCard = UIView()
    private let starsRow: StarForgeAmountRow

    private let applyButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let hintLabel = UILabel()

    private let giftHeaderLabel = UILabel()
    private let giftCard: StarForgeGiftCardView
    private let recipientAvatar = StarForgeAvatarView(frame: .zero)
    private let recipientLabel = UILabel()
    private let sendButton = UIButton(type: .system)

    private let footerLabel = UILabel()
    private let toastLabel = UILabel()

    private let starImage: UIImage
    private var starCell: CAEmitterCell?

    private var currentGift: StarForgeGift
    private let recipient: StarForgeRecipient?
    private var isTransferring = false
    private var didPerformIntro = false
    private var toastGeneration = 0

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationHaptic = UINotificationFeedbackGenerator()

    var onClose: (() -> Void)?

    init(gift: StarForgeGift, recipient: StarForgeRecipient?) {
        let starImage = StarForgeView.makeStarImage(size: 64.0, color: .white)
        self.starImage = starImage
        self.currentGift = gift
        self.recipient = recipient
        self.giftCard = StarForgeGiftCardView(gift: gift, starImage: starImage)
        self.starsRow = StarForgeAmountRow(title: "ЗВЁЗДЫ", icon: "⭐️", keyboardType: .numberPad)

        super.init(frame: .zero)

        self.setup()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        self.isOpaque = false
        self.backgroundColor = .clear
        self.clipsToBounds = true

        self.backgroundView.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1.0)
        self.backgroundView.isUserInteractionEnabled = false
        self.addSubview(self.backgroundView)

        self.gradientLayer.type = .radial
        self.gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.32)
        self.gradientLayer.endPoint = CGPoint(x: 1.25, y: 1.2)
        self.gradientLayer.colors = [
            starForgeColor(0x2A6CF6, alpha: 0.36).cgColor,
            starForgeColor(0x101A3A, alpha: 0.14).cgColor,
            UIColor.black.withAlphaComponent(0.78).cgColor
        ]
        self.gradientLayer.locations = [0.0, 0.55, 1.0]
        self.backgroundView.layer.addSublayer(self.gradientLayer)

        self.blurView.isUserInteractionEnabled = false
        self.addSubview(self.blurView)

        self.flashView.backgroundColor = .white
        self.flashView.alpha = 0.0
        self.flashView.isUserInteractionEnabled = false
        self.addSubview(self.flashView)

        self.contentView.isUserInteractionEnabled = true
        self.addSubview(self.contentView)

        self.closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        self.closeButton.tintColor = UIColor.white.withAlphaComponent(0.9)
        self.closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        self.closeButton.layer.cornerRadius = 18.0
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.contentView.addSubview(self.closeButton)

        self.titleLabel.attributedText = NSAttributedString(string: "STAR FORGE", attributes: [
            .font: UIFont.systemFont(ofSize: 16.0, weight: .heavy),
            .foregroundColor: UIColor.white,
            .kern: 3.0
        ])
        self.titleLabel.textAlignment = .center
        self.contentView.addSubview(self.titleLabel)

        self.subtitleLabel.attributedText = NSAttributedString(string: "ВИЗУАЛЬНЫЙ БАЛАНС", attributes: [
            .font: UIFont.systemFont(ofSize: 10.0, weight: .semibold),
            .foregroundColor: starForgeGoldLight.withAlphaComponent(0.85),
            .kern: 1.4
        ])
        self.subtitleLabel.textAlignment = .center
        self.contentView.addSubview(self.subtitleLabel)

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.keyboardDismissMode = .interactive
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.contentView.addSubview(self.scrollView)
        self.scrollView.addSubview(self.scrollContentView)

        self.balanceCard.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        self.balanceCard.layer.cornerRadius = 22.0
        self.balanceCard.layer.borderWidth = 1.0
        self.balanceCard.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        self.balanceCard.clipsToBounds = true
        self.scrollContentView.addSubview(self.balanceCard)

        self.balanceCard.addSubview(self.starsRow)

        self.starsRow.field.delegate = self
        self.starsRow.field.inputAccessoryView = self.makeKeyboardToolbar()

        self.applyButton.setTitle("Применить", for: .normal)
        self.applyButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .bold)
        self.applyButton.setTitleColor(UIColor(red: 0.07, green: 0.05, blue: 0.02, alpha: 1.0), for: .normal)
        self.applyButton.backgroundColor = starForgeGold
        self.applyButton.layer.shadowColor = starForgeGold.cgColor
        self.applyButton.layer.shadowOpacity = 0.35
        self.applyButton.layer.shadowRadius = 16.0
        self.applyButton.layer.shadowOffset = CGSize(width: 0.0, height: 5.0)
        self.applyButton.addTarget(self, action: #selector(self.applyPressed), for: .touchUpInside)
        self.scrollContentView.addSubview(self.applyButton)

        self.resetButton.setTitle("Сбросить к реальному", for: .normal)
        self.resetButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        self.resetButton.setTitleColor(UIColor.white.withAlphaComponent(0.75), for: .normal)
        self.resetButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        self.resetButton.layer.borderWidth = 1.0
        self.resetButton.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        self.resetButton.addTarget(self, action: #selector(self.resetPressed), for: .touchUpInside)
        self.scrollContentView.addSubview(self.resetButton)

        self.hintLabel.text = "Введи количество звёзд и нажми «Применить». Число появится в балансе Telegram — только на этом устройстве."
        self.hintLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        self.hintLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        self.hintLabel.textAlignment = .center
        self.hintLabel.numberOfLines = 0
        self.scrollContentView.addSubview(self.hintLabel)

        self.giftHeaderLabel.attributedText = NSAttributedString(string: "NFT-ПОДАРОК", attributes: [
            .font: UIFont.systemFont(ofSize: 10.0, weight: .heavy),
            .foregroundColor: starForgeGoldLight.withAlphaComponent(0.8),
            .kern: 1.8
        ])
        self.giftHeaderLabel.textAlignment = .center
        self.scrollContentView.addSubview(self.giftHeaderLabel)

        self.scrollContentView.addSubview(self.giftCard)

        self.recipientAvatar.setRecipient(recipient)
        self.scrollContentView.addSubview(self.recipientAvatar)

        self.recipientLabel.text = "Кому: \(recipient?.title ?? "Избранное")"
        self.recipientLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        self.recipientLabel.textColor = UIColor.white
        self.recipientLabel.lineBreakMode = .byTruncatingTail
        self.scrollContentView.addSubview(self.recipientLabel)

        self.sendButton.setTitle("Передать NFT-подарок", for: .normal)
        self.sendButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .bold)
        self.sendButton.setTitleColor(UIColor(red: 0.07, green: 0.05, blue: 0.02, alpha: 1.0), for: .normal)
        self.sendButton.backgroundColor = starForgeGold
        self.sendButton.layer.shadowColor = starForgeGold.cgColor
        self.sendButton.layer.shadowOpacity = 0.4
        self.sendButton.layer.shadowRadius = 18.0
        self.sendButton.layer.shadowOffset = CGSize(width: 0.0, height: 6.0)
        self.sendButton.addTarget(self, action: #selector(self.sendPressed), for: .touchUpInside)
        self.scrollContentView.addSubview(self.sendButton)

        self.footerLabel.text = "Визуальный режим. Реальные звёзды и GRAM не меняются и не тратятся."
        self.footerLabel.font = UIFont.systemFont(ofSize: 10.5, weight: .regular)
        self.footerLabel.textColor = UIColor.white.withAlphaComponent(0.35)
        self.footerLabel.textAlignment = .center
        self.footerLabel.numberOfLines = 2
        self.scrollContentView.addSubview(self.footerLabel)

        self.toastLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .bold)
        self.toastLabel.textColor = starForgeGoldLight
        self.toastLabel.textAlignment = .center
        self.toastLabel.numberOfLines = 2
        self.toastLabel.backgroundColor = UIColor.white.withAlphaComponent(0.13)
        self.toastLabel.layer.cornerRadius = 18.0
        self.toastLabel.clipsToBounds = true
        self.toastLabel.alpha = 0.0
        self.contentView.addSubview(self.toastLabel)

        self.setupEmitter()
        self.refreshRealBalances()

        if let stars = StarForgeSession.shared.starsOverride {
            self.starsRow.setOverrideText(starForgeFormattedInteger(stars))
        }
    }

    private func makeKeyboardToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(self.dismissKeyboard))
        ]
        return toolbar
    }

    private func setupEmitter() {
        let cell = CAEmitterCell()
        cell.contents = self.starImage.cgImage
        cell.birthRate = 0.0
        cell.lifetime = 1.35
        cell.lifetimeRange = 0.5
        cell.velocity = 290.0
        cell.velocityRange = 190.0
        cell.emissionRange = CGFloat.pi * 2.0
        cell.yAcceleration = 340.0
        cell.scale = 0.20
        cell.scaleRange = 0.15
        cell.spin = 2.6
        cell.spinRange = 3.4
        cell.alphaSpeed = -0.75
        cell.alphaRange = 0.2
        cell.color = starForgeGoldLight.cgColor
        self.emitterLayer.emitterCells = [cell]
        self.emitterLayer.emitterShape = .point
        self.emitterLayer.emitterMode = .points
        self.emitterLayer.renderMode = .additive
        self.emitterLayer.birthRate = 1.0
        self.emitterLayer.zPosition = 100.0
        self.starCell = cell
        self.layer.addSublayer(self.emitterLayer)
    }

    func refreshRealBalances() {
        let session = StarForgeSession.shared

        if session.hasRealStars {
            let text = starForgeFormattedInteger(session.realStars)
            self.starsRow.updatePlaceholder(text)
            self.starsRow.updateRealValue("сейчас: ⭐️ \(text)")
        } else {
            self.starsRow.updatePlaceholder("0")
            self.starsRow.updateRealValue("сейчас: —")
        }
    }

    func updateGift(_ gift: StarForgeGift) {
        self.currentGift = gift
        self.giftCard.updateGift(gift)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard self.window != nil, !self.didPerformIntro else {
            return
        }
        self.didPerformIntro = true

        self.lightHaptic.prepare()
        self.heavyHaptic.prepare()
        self.notificationHaptic.prepare()

        self.contentView.alpha = 0.0
        UIView.animate(withDuration: 0.22, animations: {
            self.contentView.alpha = 1.0
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else {
                return
            }
            self.emitStars(at: CGPoint(x: self.bounds.midX, y: self.bounds.midY), intensity: 1.0)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let bounds = self.bounds
        guard bounds.width > 0.0, bounds.height > 0.0 else {
            return
        }

        self.backgroundView.frame = bounds
        self.blurView.frame = bounds
        self.gradientLayer.frame = self.backgroundView.bounds
        self.flashView.frame = bounds
        self.emitterLayer.frame = bounds

        let contentWidth = min(bounds.width, 460.0)
        self.contentView.frame = CGRect(
            x: (bounds.width - contentWidth) * 0.5,
            y: 0.0,
            width: contentWidth,
            height: bounds.height
        )

        let width = contentWidth
        let safeTop = self.safeAreaInsets.top
        let safeBottom = self.safeAreaInsets.bottom

        self.closeButton.frame = CGRect(x: 16.0, y: safeTop + 8.0, width: 36.0, height: 36.0)
        self.titleLabel.frame = CGRect(x: 60.0, y: safeTop + 9.0, width: width - 120.0, height: 20.0)
        self.subtitleLabel.frame = CGRect(x: 60.0, y: safeTop + 29.0, width: width - 120.0, height: 14.0)

        let headerBottom = safeTop + 56.0
        self.scrollView.frame = CGRect(
            x: 0.0,
            y: headerBottom,
            width: width,
            height: max(0.0, bounds.height - headerBottom - safeBottom)
        )

        let inset: CGFloat = 16.0
        let cardWidth = width - inset * 2.0
        let rowHeight: CGFloat = 104.0
        var y: CGFloat = 4.0

        self.balanceCard.frame = CGRect(x: inset, y: y, width: cardWidth, height: rowHeight)
        self.starsRow.frame = CGRect(x: 0.0, y: 0.0, width: cardWidth, height: rowHeight)
        y = self.balanceCard.frame.maxY + 14.0

        let primaryButtonHeight: CGFloat = 52.0
        self.applyButton.frame = CGRect(x: inset, y: y, width: cardWidth, height: primaryButtonHeight)
        self.applyButton.layer.cornerRadius = primaryButtonHeight * 0.5
        y += primaryButtonHeight + 10.0

        let secondaryButtonHeight: CGFloat = 46.0
        self.resetButton.frame = CGRect(x: inset, y: y, width: cardWidth, height: secondaryButtonHeight)
        self.resetButton.layer.cornerRadius = secondaryButtonHeight * 0.5
        y += secondaryButtonHeight + 10.0

        self.hintLabel.frame = CGRect(x: inset + 8.0, y: y, width: cardWidth - 16.0, height: 50.0)
        y = self.hintLabel.frame.maxY + 18.0

        self.giftHeaderLabel.frame = CGRect(x: inset, y: y, width: cardWidth, height: 14.0)
        y += 24.0

        let giftWidth = min(190.0, cardWidth - 100.0)
        let giftHeight = giftWidth / 0.78
        self.giftCard.frame = CGRect(x: (width - giftWidth) * 0.5, y: y, width: giftWidth, height: giftHeight)
        y += giftHeight + 16.0

        let avatarSize: CGFloat = 44.0
        self.recipientAvatar.frame = CGRect(x: inset + 8.0, y: y, width: avatarSize, height: avatarSize)
        self.recipientLabel.frame = CGRect(
            x: inset + 8.0 + avatarSize + 12.0,
            y: y + 11.0,
            width: cardWidth - avatarSize - 40.0,
            height: 22.0
        )
        y += avatarSize + 14.0

        self.sendButton.frame = CGRect(x: inset, y: y, width: cardWidth, height: primaryButtonHeight)
        self.sendButton.layer.cornerRadius = primaryButtonHeight * 0.5
        y += primaryButtonHeight + 12.0

        self.footerLabel.frame = CGRect(x: inset + 8.0, y: y, width: cardWidth - 16.0, height: 34.0)
        y = self.footerLabel.frame.maxY + 20.0

        self.scrollContentView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: y)
        self.scrollView.contentSize = CGSize(width: width, height: y)

        self.toastLabel.frame = CGRect(
            x: 24.0,
            y: bounds.height - safeBottom - 62.0,
            width: width - 48.0,
            height: 46.0
        )
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let current = (textField.text ?? "") as NSString
        guard range.location <= current.length, range.location + range.length <= current.length else {
            return false
        }
        let proposed = current.replacingCharacters(in: range, with: string)
        if proposed.isEmpty {
            return true
        }

        guard proposed.count <= 18 else {
            return false
        }
        return proposed.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789 ").inverted) == nil
    }

    @objc private func dismissKeyboard() {
        self.endEditing(true)
    }

    @objc private func closePressed() {
        self.onClose?()
    }

    @objc private func applyPressed() {
        self.endEditing(true)

        let starsText = self.starsRow.text
        if starsText.isEmpty {
            StarForgeSession.shared.reset()
            self.starsRow.setOverrideText(nil)
            self.lightHaptic.impactOccurred()
            self.showToast("Показан реальный баланс")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                self?.onClose?()
            }
            return
        }

        guard let stars = starForgeParseStars(starsText) else {
            self.showToast("Неверное число звёзд")
            return
        }

        StarForgeSession.shared.apply(stars: stars)
        self.heavyHaptic.impactOccurred()
        self.flash()
        self.showToast("Баланс обновлён")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
            self?.onClose?()
        }
    }

    @objc private func resetPressed() {
        self.endEditing(true)
        StarForgeSession.shared.reset()
        self.starsRow.setOverrideText(nil)
        self.lightHaptic.impactOccurred()
        self.showToast("Показан реальный баланс")
    }

    @objc private func sendPressed() {
        guard !self.isTransferring else {
            return
        }
        guard let recipient = self.recipient else {
            self.showToast("Получатель не выбран")
            return
        }
        self.startTransfer(to: recipient)
    }

    private func startTransfer(to recipient: StarForgeRecipient) {
        self.isTransferring = true
        self.sendButton.isEnabled = false

        UIView.animate(withDuration: 0.2, animations: {
            self.sendButton.alpha = 0.55
        })

        let cardFrame = self.giftCard.convert(self.giftCard.bounds, to: self)
        guard let image = StarForgeView.snapshot(of: self.giftCard), cardFrame.width > 1.0 else {
            self.completeTransfer(to: recipient)
            return
        }

        let flyingView = UIImageView(image: image)
        flyingView.frame = cardFrame
        flyingView.contentMode = .scaleAspectFill
        flyingView.layer.cornerRadius = 20.0
        flyingView.clipsToBounds = true
        self.addSubview(flyingView)

        self.giftCard.alpha = 0.0
        self.emitStars(at: CGPoint(x: cardFrame.midX, y: cardFrame.midY), intensity: 1.3)

        let targetSize = CGSize(width: 42.0, height: 42.0)
        let avatarFrame = self.recipientAvatar.convert(self.recipientAvatar.bounds, to: self)
        let targetCenter = CGPoint(x: avatarFrame.midX, y: avatarFrame.midY)

        UIView.animate(withDuration: 0.85, delay: 0.05, options: [.curveEaseIn], animations: {
            flyingView.center = targetCenter
            flyingView.bounds = CGRect(origin: .zero, size: targetSize)
            flyingView.transform = CGAffineTransform(rotationAngle: CGFloat.pi * 1.5)
            flyingView.alpha = 0.25
        }, completion: { [weak self] _ in
            flyingView.removeFromSuperview()
            guard let self else {
                return
            }
            self.completeTransfer(to: recipient)
        })
    }

    private func completeTransfer(to recipient: StarForgeRecipient) {
        let avatarFrame = self.recipientAvatar.convert(self.recipientAvatar.bounds, to: self)
        self.emitStars(at: CGPoint(x: avatarFrame.midX, y: avatarFrame.midY), intensity: 2.0)
        self.recipientAvatar.pulse()
        self.notificationHaptic.notificationOccurred(.success)
        self.showToast("NFT-подарок отправлен\n\(recipient.title) · визуально")

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self else {
                return
            }
            self.isTransferring = false
            self.sendButton.isEnabled = true
            UIView.animate(withDuration: 0.3, animations: {
                self.sendButton.alpha = 1.0
                self.giftCard.alpha = 1.0
            })
        }
    }

    private func emitStars(at point: CGPoint, intensity: CGFloat) {
        guard let cell = self.starCell else {
            return
        }

        self.emitterLayer.emitterPosition = point
        self.emitterLayer.beginTime = CACurrentMediaTime()
        self.emitterLayer.birthRate = 1.0

        cell.birthRate = Float(150.0 * intensity)
        cell.velocity = 260.0 * intensity
        cell.velocityRange = 170.0 * intensity

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.starCell?.birthRate = 0.0
        }
    }

    private func flash() {
        self.flashView.layer.removeAllAnimations()
        self.flashView.alpha = 0.0
        UIView.animate(withDuration: 0.07, animations: {
            self.flashView.alpha = 0.22
        }, completion: { _ in
            UIView.animate(withDuration: 0.24, animations: {
                self.flashView.alpha = 0.0
            })
        })
    }

    private func showToast(_ text: String) {
        self.toastGeneration += 1
        let generation = self.toastGeneration

        self.toastLabel.text = text
        self.toastLabel.layer.removeAllAnimations()
        self.toastLabel.alpha = 0.0
        UIView.animate(withDuration: 0.2, animations: {
            self.toastLabel.alpha = 1.0
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.toastGeneration == generation else {
                return
            }
            UIView.animate(withDuration: 0.3, animations: {
                self.toastLabel.alpha = 0.0
            })
        }
    }
}

private final class StarForgeAmountRow: UIView {
    let field = UITextField()

    private let iconLabel = UILabel()
    private let titleLabel = UILabel()
    private let realLabel = UILabel()
    private let underline = UIView()

    init(title: String, icon: String, keyboardType: UIKeyboardType) {
        super.init(frame: .zero)

        self.backgroundColor = .clear

        self.iconLabel.text = icon
        self.iconLabel.font = UIFont.systemFont(ofSize: 23.0)
        self.iconLabel.textAlignment = .center
        self.addSubview(self.iconLabel)

        self.titleLabel.attributedText = NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 10.0, weight: .heavy),
            .foregroundColor: UIColor.white.withAlphaComponent(0.45),
            .kern: 1.8
        ])
        self.addSubview(self.titleLabel)

        self.field.font = UIFont.monospacedDigitSystemFont(ofSize: 30.0, weight: .bold)
        self.field.textColor = UIColor.white
        self.field.tintColor = starForgeGold
        self.field.backgroundColor = .clear
        self.field.borderStyle = .none
        self.field.keyboardType = keyboardType
        self.field.textAlignment = .left
        self.field.adjustsFontSizeToFitWidth = true
        self.field.minimumFontSize = 16.0
        self.field.textContentType = nil
        self.field.autocorrectionType = .no
        self.field.spellCheckingType = .no
        self.addSubview(self.field)

        self.underline.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        self.addSubview(self.underline)

        self.realLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .medium)
        self.realLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        self.addSubview(self.realLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String {
        return (self.field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setOverrideText(_ text: String?) {
        self.field.text = text
    }

    func updatePlaceholder(_ text: String) {
        self.field.attributedPlaceholder = NSAttributedString(string: text, attributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 30.0, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.18)
        ])
    }

    func updateRealValue(_ text: String) {
        self.realLabel.text = text
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.bounds.width
        guard width > 0.0 else {
            return
        }

        self.iconLabel.frame = CGRect(x: 16.0, y: 12.0, width: 30.0, height: 30.0)
        self.titleLabel.frame = CGRect(x: 54.0, y: 14.0, width: width - 70.0, height: 16.0)
        self.field.frame = CGRect(x: 16.0, y: 30.0, width: width - 32.0, height: 44.0)
        self.underline.frame = CGRect(x: 16.0, y: 78.0, width: width - 32.0, height: 1.0)
        self.realLabel.frame = CGRect(x: 16.0, y: 82.0, width: width - 32.0, height: 16.0)
    }
}

private final class StarForgeGiftCardView: UIView {
    private let gradientLayer = CAGradientLayer()
    private let scrimLayer = CAGradientLayer()
    private let badgeLabel = UILabel()
    private let numberLabel = UILabel()
    private let starView = UIImageView()
    private let titleLabel = UILabel()
    private let modelLabel = UILabel()

    private var gift: StarForgeGift

    init(gift: StarForgeGift, starImage: UIImage) {
        self.gift = gift

        super.init(frame: .zero)

        self.isUserInteractionEnabled = false
        self.layer.cornerRadius = 26.0
        self.layer.borderWidth = 1.0
        self.layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.45
        self.layer.shadowRadius = 26.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 14.0)

        self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.gradientLayer.cornerRadius = 26.0
        self.gradientLayer.masksToBounds = true
        self.layer.insertSublayer(self.gradientLayer, at: 0)

        self.scrimLayer.startPoint = CGPoint(x: 0.5, y: 0.45)
        self.scrimLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.scrimLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.45).cgColor
        ]
        self.scrimLayer.cornerRadius = 26.0
        self.layer.insertSublayer(self.scrimLayer, at: 1)

        self.badgeLabel.text = "NFT GIFT"
        self.badgeLabel.font = UIFont.systemFont(ofSize: 9.0, weight: .heavy)
        self.badgeLabel.textColor = UIColor.white
        self.badgeLabel.textAlignment = .center
        self.badgeLabel.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        self.badgeLabel.layer.cornerRadius = 9.0
        self.badgeLabel.clipsToBounds = true
        self.addSubview(self.badgeLabel)

        self.numberLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .semibold)
        self.numberLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        self.numberLabel.textAlignment = .right
        self.addSubview(self.numberLabel)

        self.starView.image = starImage.withRenderingMode(.alwaysTemplate)
        self.starView.tintColor = UIColor.white.withAlphaComponent(0.92)
        self.starView.contentMode = .scaleAspectFit
        self.starView.layer.shadowColor = UIColor.white.cgColor
        self.starView.layer.shadowOpacity = 0.55
        self.starView.layer.shadowRadius = 22.0
        self.starView.layer.shadowOffset = CGSize()
        self.addSubview(self.starView)

        self.titleLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .bold)
        self.titleLabel.textColor = UIColor.white
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.addSubview(self.titleLabel)

        self.modelLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .medium)
        self.modelLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        self.modelLabel.lineBreakMode = .byTruncatingTail
        self.addSubview(self.modelLabel)

        self.updateGift(gift)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateGift(_ gift: StarForgeGift) {
        self.gift = gift
        self.gradientLayer.colors = [gift.innerColor.cgColor, gift.outerColor.cgColor]
        self.titleLabel.text = gift.title
        self.modelLabel.text = gift.modelName ?? "Collectible"
        if let number = gift.number {
            self.numberLabel.text = "#\(number)"
        } else {
            self.numberLabel.text = "#—"
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.gradientLayer.frame = self.bounds
        self.scrimLayer.frame = self.bounds

        let width = self.bounds.width
        let height = self.bounds.height
        guard width > 0.0, height > 0.0 else {
            return
        }

        let padding = max(12.0, width * 0.07)
        self.badgeLabel.frame = CGRect(x: padding, y: padding, width: 62.0, height: 18.0)
        self.numberLabel.frame = CGRect(x: width - padding - 90.0, y: padding, width: 90.0, height: 18.0)

        let starSize = min(width, height) * 0.5
        self.starView.frame = CGRect(
            x: (width - starSize) * 0.5,
            y: height * 0.22,
            width: starSize,
            height: starSize
        )

        self.titleLabel.frame = CGRect(x: padding, y: height - padding - 44.0, width: width - padding * 2.0, height: 24.0)
        self.modelLabel.frame = CGRect(x: padding, y: height - padding - 20.0, width: width - padding * 2.0, height: 16.0)
    }
}

private final class StarForgeAvatarView: UIView {
    private static let palettes: [(UInt32, UInt32)] = [
        (0xFFB86B, 0xF25C54),
        (0x9BE7FF, 0x2A6CF6),
        (0xC7A6FF, 0x6A3EF5),
        (0xA8F0C6, 0x1E9E6A),
        (0xFFD37A, 0xE8A200)
    ]

    private let gradientLayer = CAGradientLayer()
    private let initialsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.layer.masksToBounds = true
        self.layer.borderWidth = 2.0
        self.layer.borderColor = UIColor.white.withAlphaComponent(0.65).cgColor
        self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.layer.addSublayer(self.gradientLayer)

        self.initialsLabel.textAlignment = .center
        self.initialsLabel.textColor = UIColor.white
        self.initialsLabel.font = UIFont.systemFont(ofSize: 19.0, weight: .semibold)
        self.addSubview(self.initialsLabel)

        self.setRecipient(nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRecipient(_ recipient: StarForgeRecipient?) {
        if let recipient {
            self.initialsLabel.text = recipient.initials
            let palette = StarForgeAvatarView.palettes[recipient.colorSeed % StarForgeAvatarView.palettes.count]
            self.gradientLayer.colors = [
                starForgeColor(palette.0).cgColor,
                starForgeColor(palette.1).cgColor
            ]
        } else {
            self.initialsLabel.text = "?"
            self.gradientLayer.colors = [
                starForgeColor(0x5A6478).cgColor,
                starForgeColor(0x2C3342).cgColor
            ]
        }
    }

    func pulse() {
        self.layer.removeAnimation(forKey: "starforge.pulse")
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [
            NSNumber(value: 1.0),
            NSNumber(value: 1.24),
            NSNumber(value: 0.95),
            NSNumber(value: 1.0)
        ]
        animation.duration = 0.5
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        self.layer.add(animation, forKey: "starforge.pulse")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let size = min(self.bounds.width, self.bounds.height)
        self.layer.cornerRadius = size * 0.5
        self.gradientLayer.frame = self.bounds
        self.gradientLayer.cornerRadius = size * 0.5
        self.initialsLabel.frame = self.bounds
    }
}
