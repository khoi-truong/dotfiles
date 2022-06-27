//___FILEHEADER___

@testable import ___PROJECTNAME___
import RIBs
import RxSwift
import RxCocoa

final class Mock___VARIABLE_productName___Interacter: ___VARIABLE_productName___Interactable {

    typealias PresenterType = Mock___VARIABLE_productName___Presenter

    var router: ___VARIABLE_productName___Routing?
    var listener: ___VARIABLE_productName___Listener?

    private let active = Variable<Bool>(false)

    var isActive: Bool {
        return active.value
    }

    var isActiveStream: Observable<Bool> {
        return active.asObservable()
    }

    func activate() {
        active.value = true
    }

    func deactivate() {
        active.value = false
    }

    var stubbedPresenter: PresenterType!
    var presenter: PresenterType {
        return stubbedPresenter
    }
}
