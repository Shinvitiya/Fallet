import Foundation

/// Recognizes quick back-and-forth movement while the mouse button is held.
struct ShakeDetector {
    private var horizontal = Axis()
    private var vertical = Axis()
    private var lastTime: TimeInterval?

    mutating func reset() {
        horizontal = Axis()
        vertical = Axis()
        lastTime = nil
    }

    mutating func sample(x: CGFloat, y: CGFloat, at time: TimeInterval) -> Bool {
        if let lastTime, time - lastTime > 0.35 { reset() }
        lastTime = time
        let shaken = horizontal.sample(x, at: time) || vertical.sample(y, at: time)
        if shaken { reset() }
        return shaken
    }

    private struct Axis {
        private var previous: CGFloat?
        private var strokeStart: CGFloat = 0
        private var direction = 0
        private var turns: [TimeInterval] = []

        mutating func sample(_ value: CGFloat, at time: TimeInterval) -> Bool {
            guard let previous else {
                self.previous = value
                strokeStart = value
                return false
            }
            self.previous = value
            let delta = value - previous
            guard abs(delta) >= 2 else { return false }
            let newDirection = delta > 0 ? 1 : -1
            if direction == 0 {
                direction = newDirection
                strokeStart = previous
                return false
            }
            guard newDirection != direction else { return false }
            guard abs(previous - strokeStart) >= 18 else { return false }

            turns.append(time)
            turns.removeAll { time - $0 > 1.2 }
            direction = newDirection
            strokeStart = previous
            return turns.count >= 2
        }
    }
}
