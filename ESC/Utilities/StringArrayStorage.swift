import Foundation

@propertyWrapper
struct StringArrayStorage {
    private var value: String = ""
    
    var wrappedValue: [String] {
        get {
            value.isEmpty ? [] : value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        set {
            value = newValue.joined(separator: ",")
        }
    }
    
    var projectedValue: String {
        get { value }
        set { value = newValue }
    }
    
    init(wrappedValue: [String] = []) {
        self.value = wrappedValue.joined(separator: ",")
    }
}