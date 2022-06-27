//___FILEHEADER___

import Foundation
import ObjectMapper

struct ___VARIABLE_productName___: Equatable {
    
    public let id: Int
}

extension ___VARIABLE_productName___: ImmutableMappable {

    init(map: Map) throws {
        self.id = try map.value("id")
    }
}
