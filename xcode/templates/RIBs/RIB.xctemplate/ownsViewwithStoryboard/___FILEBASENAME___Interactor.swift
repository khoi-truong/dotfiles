//___FILEHEADER___

import RIBs
import RxSwift
import RxCocoa

protocol ___VARIABLE_productName___Routing: ViewableRouting { }

protocol ___VARIABLE_productName___Presentable: Presentable {
    var listener: ___VARIABLE_productName___PresentableListener? { get set }
}

protocol ___VARIABLE_productName___Listener: AnyObject { }

final class ___VARIABLE_productName___Interactor: PresentableInteractor<___VARIABLE_productName___Presentable>, ___VARIABLE_productName___Interactable, ___VARIABLE_productName___PresentableListener {

    weak var router: ___VARIABLE_productName___Routing?
    weak var listener: ___VARIABLE_productName___Listener?

    // MARK: - PresentableListener

    let viewDidLoad = PublishRelay<Void>()
    let viewWillAppear = PublishRelay<Void>()

    // MARK: - Dependencies

    // MARK: - Private

    // MARK: - Life-cycle

    override init(presenter: ___VARIABLE_productName___Presentable) {
        super.init(presenter: presenter)
        presenter.listener = self
    }

    override func didBecomeActive() {
        super.didBecomeActive()
        setUpPresenter()
        setUpRouting()
        setUpListener()
        setUpDownStream()
        setUpInteractor()
        setUpAnalytics()
    }

    override func willResignActive() {
        super.willResignActive()
    }

    // MARK: - Binding

    private func setUpPresenter() {
        // Set up logic to bind to ___VARIABLE_productName___Presentable here
    }

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

    // MARK: - Analytics

    private func setUpAnalytics() {
        // Set up events for tracking here
    }
}
