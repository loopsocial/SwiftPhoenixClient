/*

Converts A class to a dictionary, used for serializing dictionaries to JSON

Supported objects:
- Serializable derived classes
- Arrays of Serializable
- NSData
- String, Numeric, and all other NSJSONSerialization supported objects

*/

import Foundation

public class Serializable : NSObject {

    func toDictionary() -> [String: Any] {
        let aClass : AnyClass? = type(of: self)
        var propertiesCount : CUnsignedInt = 0
        let propertiesInAClass : UnsafeMutablePointer<objc_property_t?>! = class_copyPropertyList(aClass, &propertiesCount)
        var propertiesDictionary = [String: Any]()

        for i in 0 ..< Int(propertiesCount) {
            let property = propertiesInAClass[i]
            let propName = String(cString: property_getName(property))
            let propValue = value(forKey: propName)

            if let propValue = propValue as? Serializable {
                propertiesDictionary[propName] = propValue.toDictionary()
            } else if let propValue = propValue as? [Serializable] {
                propertiesDictionary[propName] = propValue.map { $0.toDictionary() }
            } else if let propValue = propValue as? Data {
                propertiesDictionary[propName] = propValue.base64EncodedString(options: [])
            } else if let propValue = propValue as? Bool {
                propertiesDictionary[propName] = [propValue]
            } else if let propValue = propValue as? Date {
                propertiesDictionary[propName] = propValue.string
            } else {
                propertiesDictionary[propName] = propValue
            }
        }

        return propertiesDictionary
    }

    func toJson() -> Data {
        let dictionary = self.toDictionary()
        do {
            return try JSONSerialization.data(withJSONObject: dictionary, options:JSONSerialization.WritingOptions(rawValue: 0))
        } catch _ {
            return Data()
        }
    }

    public func toJsonString() -> NSString! {
        return NSString(data: self.toJson() as Data, encoding: String.Encoding.utf8.rawValue)
    }
    
    override init() { }
}

fileprivate extension Date {
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "Z"
        return df
    }()

    var string: String {
        return NSString(format: "/Date(%.0f000%@)/", timeIntervalSince1970, Date.dateFormatter.string(from: self)) as String
    }
}
