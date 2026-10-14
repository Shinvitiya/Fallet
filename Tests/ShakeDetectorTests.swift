import Foundation

@main
struct ShakeDetectorTests {
    static func main() {
        var detector = ShakeDetector()
        let straight = stride(from: 0.0, through: 120.0, by: 5.0)
        for (index, x) in straight.enumerated() {
            precondition(!detector.sample(x: x, y: 0, at: Double(index) * 0.02))
        }

        detector.reset()
        let jitter: [CGFloat] = [0, 8, 2, 10, 1, 9, 3, 7, 0]
        for (index, x) in jitter.enumerated() {
            precondition(!detector.sample(x: x, y: 0, at: Double(index) * 0.04))
        }

        detector.reset()
        let shake: [CGFloat] = [0, 10, 20, 30, 40, 30, 20, 10, 0, 10, 20, 30, 40, 30]
        let results = shake.enumerated().map { index, x in
            detector.sample(x: x, y: 0, at: Double(index) * 0.04)
        }
        precondition(results.filter { $0 }.count == 1)

        detector.reset()
        let verticalResults = shake.enumerated().map { index, y in
            detector.sample(x: 0, y: y, at: Double(index) * 0.04)
        }
        precondition(verticalResults.filter { $0 }.count == 1)

        detector.reset()
        let paused: [(CGFloat, TimeInterval)] = [(0, 0), (40, 0.1), (30, 0.5), (0, 0.6), (40, 0.7)]
        for (x, time) in paused {
            precondition(!detector.sample(x: x, y: 0, at: time))
        }

        print("ShakeDetector tests passed")
    }
}
