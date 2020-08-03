// Project Pappe
// Copyright 2020, Framework Labs.

import Foundation
import Combine

public enum VarBehavior {
    case persist
    case reset
}

public struct VarConfig {
    public let name: String
    public let value: Any
    public let behavior: VarBehavior
    
    public init(_ n: String, _ v: Any, _ b: VarBehavior = .persist) {
        name = n
        value = v
        behavior = b
    }
}

@dynamicMemberLookup
public class Reactor {
    public typealias ReactCallback = (TickResult) -> Void
    
    let inConfig: [VarConfig]
    let inOutConfig: [VarConfig]
    let queue: DispatchQueue

    let proc: Processor
    var cb: ReactCallback?
    var vars: [String: Any] = [:]
            
    public init(module: Module, entryPoint: String = "Main", inConfig: [VarConfig], inOutConfig: [VarConfig], queue: DispatchQueue = DispatchQueue(label: "Reactor")) throws {
        self.inConfig = inConfig
        self.inOutConfig = inOutConfig
        self.queue = queue
        
        proc = try Processor(module: module, entryPoint: entryPoint)
        proc.receiveCtx = ReceiveCtx(queue: queue) {
            self.doReact()
        }
        
        for cfg in inConfig + inOutConfig {
            vars[cfg.name] = cfg.value
        }
    }
    
    /// Note: Not thread safe! Must only be called on the reactors queue or right after the beginning!
    public subscript(dynamicMember name: String) -> Any {
        get {
            return vars[name]!
        }
        set {
            vars[name] = newValue
        }
    }
    
    public func react(dispatchOnQueue: Bool = true) {
        maybeDispatchOnQueue(dispatchOnQueue) {
            self.doReact()
        }
    }
    
    /// Note: Not thread safe! Must only be called on the reactors queue or right after the beginning!
    public var reactCallback: ReactCallback? {
        get {
            return cb
        }
        set {
            cb = newValue
        }
    }
    
    public func maybeDispatchOnQueue(_ dispatchOnQueue: Bool, thunk: @escaping () -> Void) {
        if dispatchOnQueue {
            queue.async(execute: thunk)
        } else {
            thunk()
        }
    }
    
    func doReact() {
        step()
    }
    
    func step() {
        let vals = inConfig.map { cfg in self.vars[cfg.name]! }
        let locs = inOutConfig.map { cfg in DirectLoc(val: self.vars[cfg.name]!) }
        
        let res = try! self.proc.tick(vals, locs)
        
        for (cfg, loc) in zip(inOutConfig, locs) {
            self.vars[cfg.name] = loc.val
        }
        
        self.reactCallback?(res)

        for cfg in inConfig + inOutConfig {
            if cfg.behavior == .reset {
                self.vars[cfg.name] = cfg.value
            }
        }
    }
}

// MARK: - Combine extensions

@available(OSX 10.15, *)
extension Reactor {
    
    public func publisher(for v: String, dispatchOnQueue: Bool = true) -> AnyPublisher<Any, Never> {
        let res = PassthroughSubject<Any, Never>()
        maybeDispatchOnQueue(dispatchOnQueue) {
            let oldCB = self.reactCallback
            self.reactCallback = { tr in
                oldCB?(tr)
                res.send(self[dynamicMember: v])
                switch tr {
                case .done, .result(_):
                    res.send(completion: .finished)
                default:
                    break
                }
            }
        }
        return res.eraseToAnyPublisher()
    }    
}

@available(OSX 10.15, *)
public extension Receiver {
    
    func connect(_ p: AnyPublisher<Any, Never>, reactOnValue: Bool = true, reactOnCompletion: Bool = true) {
        box = p.sink(receiveCompletion: { [weak self] _ in
            self?.postDone()
            if reactOnCompletion {
                self?.react()
            }
        }, receiveValue: { [weak self] val in
            self?.postValue(val)
            if reactOnValue {
                self?.react()
            }
        })
    }
}

@available(OSX 10.15, *)
public func receive(_ outArg: @autoclosure @escaping LFunc, resetTo value: Any? = nil, reactOnValue: @autoclosure @escaping () -> Bool = true, reactOnCompletion: @autoclosure @escaping () -> Bool = true, _ pub: @escaping () -> AnyPublisher<Any, Never>) -> Stmt {
    receive(outArg(), resetTo: value) { rcv in
        rcv.connect(pub(), reactOnValue: reactOnValue(), reactOnCompletion: reactOnCompletion())
    }
}

@available(OSX 10.15, *)
public extension Publisher where Self.Failure == Never {
    
    func react(_ r: Reactor, _ port: String) -> Reactor {
        _ = self.sink { val in
            r.maybeDispatchOnQueue(true) {
                r[dynamicMember: port] = val
                r.react(dispatchOnQueue: false)
            }
        }
        return r
    }
}

@available(OSX 10.15, *)
public extension Publisher {
    
    func eraseTotally() -> AnyPublisher<Any, Self.Failure> {
        self.map { $0 as Any }.eraseToAnyPublisher()
    }
}
