import SwiftUI

/// Fast, lightweight SVG path `d` string parser for SwiftUI `Path`.
public struct SVGPathParser {
    public static func parse(_ d: String) -> Path {
        var path = Path()
        var currentPoint = CGPoint.zero
        var subpathStart = CGPoint.zero
        
        let tokens = tokenize(d)
        var i = 0
        var currentCommand: Character = "M"
        
        while i < tokens.count {
            let token = tokens[i]
            if token.count == 1, let char = token.first, char.isLetter {
                currentCommand = char
                i += 1
                continue
            }
            
            switch currentCommand {
            case "M": // Absolute MoveTo
                if i + 1 < tokens.count, let x = Double(tokens[i]), let y = Double(tokens[i+1]) {
                    currentPoint = CGPoint(x: x, y: y)
                    subpathStart = currentPoint
                    path.move(to: currentPoint)
                    i += 2
                    currentCommand = "L"
                } else { i += 1 }
                
            case "m": // Relative MoveTo
                if i + 1 < tokens.count, let dx = Double(tokens[i]), let dy = Double(tokens[i+1]) {
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    subpathStart = currentPoint
                    path.move(to: currentPoint)
                    i += 2
                    currentCommand = "l"
                } else { i += 1 }
                
            case "L": // Absolute LineTo
                if i + 1 < tokens.count, let x = Double(tokens[i]), let y = Double(tokens[i+1]) {
                    currentPoint = CGPoint(x: x, y: y)
                    path.addLine(to: currentPoint)
                    i += 2
                } else { i += 1 }
                
            case "l": // Relative LineTo
                if i + 1 < tokens.count, let dx = Double(tokens[i]), let dy = Double(tokens[i+1]) {
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y + dy)
                    path.addLine(to: currentPoint)
                    i += 2
                } else { i += 1 }
                
            case "H": // Absolute Horizontal Line
                if let x = Double(tokens[i]) {
                    currentPoint = CGPoint(x: x, y: currentPoint.y)
                    path.addLine(to: currentPoint)
                    i += 1
                } else { i += 1 }
                
            case "h": // Relative Horizontal Line
                if let dx = Double(tokens[i]) {
                    currentPoint = CGPoint(x: currentPoint.x + dx, y: currentPoint.y)
                    path.addLine(to: currentPoint)
                    i += 1
                } else { i += 1 }
                
            case "V": // Absolute Vertical Line
                if let y = Double(tokens[i]) {
                    currentPoint = CGPoint(x: currentPoint.x, y: y)
                    path.addLine(to: currentPoint)
                    i += 1
                } else { i += 1 }
                
            case "v": // Relative Vertical Line
                if let dy = Double(tokens[i]) {
                    currentPoint = CGPoint(x: currentPoint.x, y: currentPoint.y + dy)
                    path.addLine(to: currentPoint)
                    i += 1
                } else { i += 1 }
                
            case "C": // Absolute Cubic Bezier
                if i + 5 < tokens.count,
                   let cp1x = Double(tokens[i]), let cp1y = Double(tokens[i+1]),
                   let cp2x = Double(tokens[i+2]), let cp2y = Double(tokens[i+3]),
                   let ex = Double(tokens[i+4]), let ey = Double(tokens[i+5]) {
                    let cp1 = CGPoint(x: cp1x, y: cp1y)
                    let cp2 = CGPoint(x: cp2x, y: cp2y)
                    currentPoint = CGPoint(x: ex, y: ey)
                    path.addCurve(to: currentPoint, control1: cp1, control2: cp2)
                    i += 6
                } else { i += 1 }
                
            case "c": // Relative Cubic Bezier
                if i + 5 < tokens.count,
                   let dcp1x = Double(tokens[i]), let dcp1y = Double(tokens[i+1]),
                   let dcp2x = Double(tokens[i+2]), let dcp2y = Double(tokens[i+3]),
                   let dex = Double(tokens[i+4]), let dey = Double(tokens[i+5]) {
                    let cp1 = CGPoint(x: currentPoint.x + dcp1x, y: currentPoint.y + dcp1y)
                    let cp2 = CGPoint(x: currentPoint.x + dcp2x, y: currentPoint.y + dcp2y)
                    currentPoint = CGPoint(x: currentPoint.x + dex, y: currentPoint.y + dey)
                    path.addCurve(to: currentPoint, control1: cp1, control2: cp2)
                    i += 6
                } else { i += 1 }
                
            case "Q": // Absolute Quadratic Bezier
                if i + 3 < tokens.count,
                   let cpx = Double(tokens[i]), let cpy = Double(tokens[i+1]),
                   let ex = Double(tokens[i+2]), let ey = Double(tokens[i+3]) {
                    let cp = CGPoint(x: cpx, y: cpy)
                    currentPoint = CGPoint(x: ex, y: ey)
                    path.addQuadCurve(to: currentPoint, control: cp)
                    i += 4
                } else { i += 1 }
                
            case "q": // Relative Quadratic Bezier
                if i + 3 < tokens.count,
                   let dcpx = Double(tokens[i]), let dcpy = Double(tokens[i+1]),
                   let dex = Double(tokens[i+2]), let dey = Double(tokens[i+3]) {
                    let cp = CGPoint(x: currentPoint.x + dcpx, y: currentPoint.y + dcpy)
                    currentPoint = CGPoint(x: currentPoint.x + dex, y: currentPoint.y + dey)
                    path.addQuadCurve(to: currentPoint, control: cp)
                    i += 4
                } else { i += 1 }
                
            case "A", "a": // Elliptical arc fallback to line
                if i + 6 < tokens.count,
                   let ex = Double(tokens[i+5]), let ey = Double(tokens[i+6]) {
                    if currentCommand == "A" {
                        currentPoint = CGPoint(x: ex, y: ey)
                    } else {
                        currentPoint = CGPoint(x: currentPoint.x + ex, y: currentPoint.y + ey)
                    }
                    path.addLine(to: currentPoint)
                    i += 7
                } else { i += 1 }
                
            case "Z", "z":
                path.closeSubpath()
                currentPoint = subpathStart
                i += 1
                
            default:
                i += 1
            }
        }
        
        return path
    }
    
    private static func tokenize(_ pathString: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""
        
        for char in pathString {
            if char.isLetter {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                tokens.append(String(char))
            } else if char == "," || char.isWhitespace {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
            } else if char == "-" {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                currentToken.append(char)
            } else {
                currentToken.append(char)
            }
        }
        
        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }
        
        return tokens
    }
}
