//___FILEHEADER___

@testable import ___PROJECTNAME___
import RIBs
import RxSwift
import RxCocoa

final class Mock___VARIABLE_productName___Builder: ___VARIABLE_productName___Buildable {
    var invokedBuild = false
    var invokedBuildCount = 0
    var stubbedBuildResult: ___VARIABLE_productName___Routing?

    func build(withListener listener: ___VARIABLE_productName___Listener) -> ___VARIABLE_productName___Routing {
        invokedBuild = true
        invokedBuildCount += 1

        guard let stubbedBuildResult = stubbedBuildResult else {
            fatalError("Builder expected to be set ")
        }
        return stubbedBuildResult
    }
}
