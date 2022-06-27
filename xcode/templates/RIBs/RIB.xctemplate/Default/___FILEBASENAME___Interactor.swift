//___FILEHEADER___

import RIBs
import RxSwift

protocol ___VARIABLE_productName___Routing: Routing {
    func cleanupViews()
}

protocol ___VARIABLE_productName___Listener: AnyObject { }

final class ___VARIABLE_productName___Interactor: Interactor, ___VARIABLE_productName___Interactable {

    weak var router: ___VARIABLE_productName___Routing?
    weak var listener: ___VARIABLE_productName___Listener?

    // MARK: - Dependencies

    // MARK: - Life-cycle

    override init() {}

    override func didBecomeActive() {
        super.didBecomeActive()
        setUpRouting()
        setUpListener()
        setUpDownStream()
        setUpInteractor()
    }

    override func willResignActive() {
        super.willResignActive()
        router?.cleanupViews()
    }

    // MARK: - Binding

    private func setUpRouting() {
        // Set up logic to route to children RIBs via ___VARIABLE_productName___Routing here
    }
    
    private func setUpListener() {
        // Set up logic to upstream via ___VARIABLE_productName___Listener here
    }

    private func setUpDownStream() {
        // Set up logic to downstream via some mutable streams in ___VARIABLE_productName___Component here
    }

    private func setUpInteractor() {
        // Set up internal logic inside ___VARIABLE_productName___Interactor
        // such as handle services and streams from parent RIBs here
    }
}
