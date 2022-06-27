//___FILEHEADER___

import RIBs
import RxCocoa
import RxSwift
import UIKit

protocol ___VARIABLE_productName___PresentableListener: AnyObject {
    var viewDidLoad: PublishRelay<Void> { get }
    var viewWillAppear: PublishRelay<Void> { get }
}

final class ___VARIABLE_productName___ViewController: UIViewController, ___VARIABLE_productName___Presentable, ___VARIABLE_productName___ViewControllable {

    weak var listener: ___VARIABLE_productName___PresentableListener?

    // MARK: - UI

    // MARK: - Presenter

    // MARK: - Private

    private let disposeBag = DisposeBag()

    // MARK: - Life-cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpView()
        setUpPresenter()
        setUpPresentableListener()
        listener?.viewDidLoad.accept(())
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        listener?.viewWillAppear.accept(())
    }

    // MARK: - Set up

    private func setUpView() {
        // Set up and config UI here
    }

    // MARK: - Binding

    private func setUpPresenter() {
        // Set up binding data from interactor and presenting UI here
    }

    private func setUpPresentableListener() {
        // Set up callback events from user interactions to interactor
    }
}
