import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import LocalizedPeerData
import SwiftSignalKit

final class StarForgeController: ViewController {
    private let context: AccountContext
    private let peer: EnginePeer?

    private var forgeView: StarForgeView?
    private var starsDisposable: Disposable?
    private var giftsDisposable: Disposable?
    private var giftsContext: ProfileGiftsContext?

    init(context: AccountContext, peer: EnginePeer?) {
        self.context = context
        self.peer = peer

        super.init(navigationBarPresentationData: nil)

        self.displayNavigationBar = false
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.starsDisposable?.dispose()
        self.giftsDisposable?.dispose()
    }

    override func loadView() {
        super.loadView()

        self.view.backgroundColor = .clear
        self.view.clipsToBounds = true

        let recipient = self.peer.flatMap { peer -> StarForgeRecipient? in
            let title = peer.compactDisplayTitle
            if title.isEmpty {
                return nil
            }
            return StarForgeRecipient(title: title)
        } ?? StarForgeRecipient(title: "Избранное")

        let forgeView = StarForgeView(gift: StarForgeGift.fallback, recipient: recipient)
        forgeView.onClose = { [weak self] in
            self?.dismiss(animated: true)
        }
        forgeView.frame = self.view.bounds
        forgeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(forgeView)
        self.forgeView = forgeView

        if let starsContext = self.context.starsContext {
            self.starsDisposable = (starsContext.state
            |> deliverOnMainQueue).start(next: { [weak self] state in
                guard let self, let state else {
                    return
                }
                StarForgeSession.shared.updateRealStars(state.balance.value)
                self.forgeView?.refreshRealBalances()
            })
        }

        let giftsContext = ProfileGiftsContext(
            account: self.context.account,
            peerId: self.context.account.peerId,
            filter: [.unique, .displayed, .hidden]
        )
        self.giftsContext = giftsContext
        self.giftsDisposable = (giftsContext.state
        |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self else {
                return
            }
            for gift in state.filteredGifts {
                if case let .unique(uniqueGift) = gift.gift {
                    self.forgeView?.updateGift(StarForgeGift(uniqueGift: uniqueGift))
                    break
                }
            }
        })
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        if let forgeView = self.forgeView {
            forgeView.frame = CGRect(origin: .zero, size: layout.size)
        }
    }
}
