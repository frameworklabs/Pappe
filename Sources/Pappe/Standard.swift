// Project Pappe
// Copyright 2020, Framework Labs.

import Foundation

@available(OSX 10.15, *)
public let clockModule = Module { name in
    
    activity (name.Clock, [name.interval, name.shouldReact]) { val in
        exec { val.tick = false }
        receive (val.loc.tick, resetTo: false, reactOnValue: val.shouldReact as Bool) {
            Timer.publish(every: val.interval, on: .main, in: .default).autoconnect().map { _ in return true }.eraseToAnyPublisher()
        }
    }
}
