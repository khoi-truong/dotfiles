//___FILEHEADER___

import RIBs

protocol ___VARIABLE_productName___Dependency: Dependency { }

final class ___VARIABLE_productName___Component: Component<___VARIABLE_productName___Dependency> { }

// MARK: - Builder

protocol ___VARIABLE_productName___Buildable: Buildable {
    func build(withListener listener: ___VARIABLE_productName___Listener) -> ___VARIABLE_productName___Routing
}

final class ___VARIABLE_productName___Builder: Builder<___VARIABLE_productName___Dependency>, ___VARIABLE_productName___Buildable {

    override init(dependency: ___VARIABLE_productName___Dependency) {
        super.init(dependency: dependency)
    }

    func build(withListener listener: ___VARIABLE_productName___Listener) -> ___VARIABLE_productName___Routing {
        let viewController = ___VARIABLE_productName___ViewController()
        let component = ___VARIABLE_productName___Component(dependency: dependency)
        let interactor = ___VARIABLE_productName___Interactor(presenter: viewController)
        interactor.listener = listener
        return ___VARIABLE_productName___Router(interactor: interactor, viewController: viewController)
    }
}
