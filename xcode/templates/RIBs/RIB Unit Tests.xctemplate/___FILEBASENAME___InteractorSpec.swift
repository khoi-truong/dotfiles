//___FILEHEADER___

@testable import ___PROJECTNAME___
import Quick
import Nimble
import RxCocoa
import RxSwift
import RxTest

final class ___VARIABLE_productName___InteractorSpec: QuickSpec {

    override func spec() {
        var sut: ___VARIABLE_productName___Interactor!
        var presenter: Mock___VARIABLE_productName___Presenter!
        var router: Mock___VARIABLE_productName___Router!

        beforeEach {
            presenter = Mock___VARIABLE_productName___Presenter()
            router = Mock___VARIABLE_productName___Router()
            sut = ___VARIABLE_productName___Interactor(presenter: presenter)
            sut.router = router
        }

        describe("init") {
            it("sets presenter.listener to self") {
                expect(presenter.listener) === sut
            }
        }
    }
}