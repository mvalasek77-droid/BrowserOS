import SwiftUI
import Combine

@MainActor
class BrowserViewModel: ObservableObject {
    @Published var addressBarText: String = ""
    @Published var isAddressBarFocused: Bool = false
    @Published var display: PageDisplay = PageDisplay()
    @Published var isPhoneReachable: Bool = false

    private(set) var currentURL: String = ""
    private var activeTabId: UUID?
    private let sessionManager = WatchSessionManager.shared
    private var cancellables: Set<AnyCancellable> = []
    private var isActivated = false

    func activate(tabId: UUID) {
        activeTabId = tabId
        guard !isActivated else { return }
        isActivated = true

        sessionManager.$pageDisplay
            .receive(on: RunLoop.main)
            .sink { [weak self] newDisplay in
                guard let self else { return }
                self.display = newDisplay
                if !newDisplay.url.isEmpty {
                    self.currentURL = newDisplay.url
                    self.addressBarText = newDisplay.url
                }
            }
            .store(in: &cancellables)

        isPhoneReachable = sessionManager.isPhoneReachable
        sessionManager.$isPhoneReachable
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] reachable in
                self?.isPhoneReachable = reachable
            }
            .store(in: &cancellables)
    }

    func loadPage(url: String) {
        currentURL = url
        addressBarText = url
        display = PageDisplay(
            content: .loading,
            url: url,
            title: URL(string: url)?.host ?? SteroidBrand.name
        )
        if sessionManager.isPhoneReachable {
            sessionManager.loadURL(url)
        } else {
            display = PageDisplay(content: .error("iPhone not connected"), url: url, title: "")
        }
    }

    func resetDisplay() {
        display = PageDisplay()
        currentURL = ""
    }

    func goBackOnPhone() {
        sessionManager.goBack()
    }

    func goForwardOnPhone() {
        sessionManager.goForward()
    }

    func openOnIPhoneToLogin() {
        var url = currentURL
        if case .loginRequired(let info) = display.content, !info.url.isEmpty {
            url = info.url
        }
        guard !url.isEmpty else { return }
        sessionManager.openOnIPhoneLogin(url: url)
    }

    func submitAddress(@ObservedObject state: BrowserState) {
        let text = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.navigate(to: text)
        isAddressBarFocused = false
    }

    func toggleReaderMode(@ObservedObject state: BrowserState) {
        state.updateActiveTab { tab in
            tab.isReaderMode.toggle()
        }
    }
}
