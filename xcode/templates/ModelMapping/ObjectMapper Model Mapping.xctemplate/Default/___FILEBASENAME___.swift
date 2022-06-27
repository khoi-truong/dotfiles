//___FILEHEADER___

import Foundation
import ObjectMapper

struct ___VARIABLE_productName___: Equatable {
    
    public var id: Int
}

extension ___VARIABLE_productName___: Mappable {

    init?(map: Map) {
        guard let id = map.JSON["id"] as? Int, id >= 0 else { return nil }
        self.id = id
    }

    mutating func mapping(map: Map) {
        id <- map["id"]
    }
}
