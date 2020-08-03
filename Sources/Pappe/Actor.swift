// Project Pappe
// Copyright 2020, Framework Labs.

import Foundation
import Combine

@available(OSX 10.15, *)
public class Actor : Reactor {
    
    var timerConnection: Cancellable?
    
    public func start(interval: TimeInterval, dispatchOnQueue: Bool = true) -> Self {
        maybeDispatchOnQueue(dispatchOnQueue) {
            self.timerConnection = self.setupTimer(interval: interval)
            self.step()
        }
        return self
    }
    
    public func stop(dispatchOnQueue: Bool = true) {
        maybeDispatchOnQueue(dispatchOnQueue) {
            self.timerConnection = nil
        }
    }

    override func doReact() {
        // Empty - Actor is active not reactive.
    }
    
    func setupTimer(interval: TimeInterval) -> Cancellable {
        return Timer.publish(every: interval, on: .main, in: .default).autoconnect().receive(on: queue).sink { _ in
            self.step()
        }
    }
}
