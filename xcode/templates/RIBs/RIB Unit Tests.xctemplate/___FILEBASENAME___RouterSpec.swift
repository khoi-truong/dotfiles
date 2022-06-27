//___FILEHEADER___

@testable import ___PROJECTNAME___
import Quick
import Nimble
import RxSwift
import RxCocoa
import RxTest

final class ___VARIABLE_productName___RouterSpec: QuickSpec {

    override func spec() {
        var sut: ___VARIABLE_productName___Router!
        var interactor: Mock___VARIABLE_productName___Interacter!
        var viewController: Mock___VARIABLE_productName___ViewController!

        beforeEach {
            interactor = Mock___VARIABLE_productName___Interacter()
            viewController = Mock___VARIABLE_productName___ViewController()
            sut = ___VARIABLE_productName___Router(interactor: interactor, viewController: viewController)
        }

        describe("init") {
            it("sets interactor.router to self") {
                expect(interactor.router) === sut
            }
        }
    }
}