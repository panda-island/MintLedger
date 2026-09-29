import Foundation

enum AmountExpression {
    static func evaluate(_ input: String) -> Double? {
        let expression = input
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard !expression.isEmpty else { return nil }

        var values: [Double] = []
        var operators: [Character] = []
        var number = ""

        func precedence(_ op: Character) -> Int { (op == "*" || op == "/") ? 2 : 1 }
        func applyTop() -> Bool {
            guard let op = operators.popLast(), values.count >= 2 else { return false }
            let rhs = values.removeLast()
            let lhs = values.removeLast()
            let result: Double
            switch op {
            case "+": result = lhs + rhs
            case "-": result = lhs - rhs
            case "*": result = lhs * rhs
            case "/":
                guard rhs != 0 else { return false }
                result = lhs / rhs
            default: return false
            }
            values.append(result)
            return true
        }

        for character in expression {
            if character.isNumber || character == "." {
                number.append(character)
            } else if "+-*/".contains(character) {
                guard let value = Double(number) else { return nil }
                values.append(value)
                number = ""
                while let top = operators.last, precedence(top) >= precedence(character) {
                    guard applyTop() else { return nil }
                }
                operators.append(character)
            } else {
                return nil
            }
        }
        guard let final = Double(number) else { return nil }
        values.append(final)
        while !operators.isEmpty { guard applyTop() else { return nil } }
        guard values.count == 1, let result = values.first, result.isFinite, result > 0 else { return nil }
        return result
    }

    static func formatted(_ value: Double) -> String {
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    static func appending(_ operation: String, to expression: String) -> String {
        guard !expression.isEmpty else { return expression }
        let operations = "+−×÷"
        var result = expression
        if let last = result.last, operations.contains(last) { result.removeLast() }
        result.append(operation)
        return result
    }
}
