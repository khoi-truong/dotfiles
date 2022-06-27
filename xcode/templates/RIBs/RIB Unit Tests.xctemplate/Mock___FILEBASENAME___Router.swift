//___FILEHEADER___

@testable import ___PROJECTNAME___
import RIBs
import RxSwift
import RxCocoa

final class Mock___VARIABLE_productName___Router: ___VARIABLE_productName___Routing {
    let viewControllable: ViewControllable
    let interactable: Interactable

    let children: [Routing] = []

    init(interactable: Interactable, viewControllable: ViewControllable) {
        self.interactable = interactable
        self.viewControllable = viewControllable
    }

    var invokedLifecycleGetter = false
    var invokedLifecycleGetterCount = 0
    lazy var stubbedLifecycle = PublishSubject<RouterLifecycle>()
    var lifecycle: Observable<RouterLifecycle> {
        invokedLifecycleGetter = true
        invokedLifecycleGetterCount += 1
        return stubbedLifecycle.asObservable()
    }

    var invokedLoad = false
    var invokedLoadCount = 0
    func load() {
        invokedLoad = true
        invokedLoadCount += 1
    }

    var invokedAttachChild = false
    var invokedAttachChildCount = 0
    var invokedAttachChildParameters: (child: Routing, Void)?
    func attachChild(_ child: Routing) {
        invokedAttachChild = true
        invokedAttachChildCount += 1
        invokedAttachChildParameters = (child, ())
    }

    var invokedDetachChild = false
    var invokedDetachChildCount = 0
    var invokedDetachChildParameters: (child: Routing, Void)?
    func detachChild(_ child: Routing) {
        invokedDetachChild = true
        invokedDetachChildCount += 1
        invokedDetachChildParameters = (child, ())
    }
}
