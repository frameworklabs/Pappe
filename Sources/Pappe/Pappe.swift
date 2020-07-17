// Pappe
// Copyright 2020, Framework Labs.

import Foundation
import Combine

public enum Errors : Error {
    case varNotFound(String)
    case activityNotFound(String)
    case exitNotAllowed
}

public protocol Loc {
    var val: Any { get set }
}

public class DirectLoc : Loc {
    public var val: Any
    public init(val: Any) {
        self.val = val
    }
}

struct CtxLoc : Loc {
    let name: String
    var ctx: Ctx
    
    var val: Any {
        get {
            return ctx[dynamicMember: name]
        }
        set {
            ctx[dynamicMember: name] = newValue
        }
    }
}

@dynamicMemberLookup
public struct Locs {
    let ctx: Ctx
    
    public subscript(dynamicMember name: String) -> Loc {
        return CtxLoc(name: name, ctx: ctx)
    }
}

@dynamicMemberLookup
public class Ctx {
    let parent: Ctx?
    var map: [String: Any] = [:]
    
    public lazy var loc: Locs = Locs(ctx: self)
    
    init(_ parent: Ctx? = nil) {
        self.parent = parent
    }
    
    public subscript<T>(dynamicMember name: String) -> T {
        get {
            if let val = map[name] {
                return val as! T
            }
            if let p = parent {
                return p[dynamicMember: name]
            }
            fatalError("\(name) is not a variable!")
        }
        set {
            if let _ = map[name] {
                map[name] = newValue
                return
            }
            if let p = parent {
                p[dynamicMember: name] = newValue
            }
            map[name] = newValue
        }
    }
}

@dynamicMemberLookup
public struct ID {
    public subscript(dynamicMember name: String) -> String {
        return name
    }
}

public typealias Proc = () -> Void
public typealias Func = () -> Any
public typealias LFunc = () -> Loc
public typealias PFunc = (Receiver) -> Void
public typealias MFunc = () -> [Any]
public typealias MLFunc = () -> [Loc]
public typealias Cond = () -> Bool
public typealias ResFunc = (Any?) -> Void

public enum Stmt {
    case await(Cond)
    case receive(LFunc, Any?, PFunc)
    case run(String, MFunc, MLFunc, ResFunc?)
    case cobegin([Trail])
    case repeatUntil([Stmt], Cond)
    case whenAbort(Cond, [Stmt])
    case match([Conditional])
    case exec(Proc)
    case exit(Func)
    case nop
}

public enum Trail {
    case strong([Stmt])
    case weak([Stmt])
}

public typealias Conditional = (Cond, [Stmt])

public struct Activity {
    let name: String
    let inParams: [String]
    let outParams: [String]
    let builder: (Ctx) -> [Stmt]
    
    init(name: String, inParams: [String], outParams: [String], @StmtBuilder builder: @escaping (Ctx) -> [Stmt]) {
        self.name = name
        self.inParams = inParams
        self.outParams = outParams
        self.builder = builder
    }
    
    func makeStmts(_ ctx: Ctx) -> [Stmt] {
        builder(ctx)
    }
}

@_functionBuilder
public struct StmtBuilder {
    public static func buildBlock(_ stmts: Stmt...) -> [Stmt] {
        return stmts
    }
}

@_functionBuilder
public struct TrailBuilder {
    public static func buildBlock(_ trails: Trail...) -> [Trail] {
        return trails
    }
}

@_functionBuilder
public struct ConditionalBuilder {
    public static func buildBlock(_ conds: Conditional...) -> [Conditional] {
        return conds
    }
}

@_functionBuilder
public struct ActivityBuilder {
    public static func buildBlock(_ acts: Activity...) -> [Activity] {
        return acts
    }
}

public func await(_ cond: @escaping Cond) -> Stmt {
    Stmt.await(cond)
}

public func receive(_ outArg: @autoclosure @escaping LFunc, resetTo value: Any? = nil, _ pfun: @escaping PFunc) -> Stmt {
    Stmt.receive(outArg, value, pfun)
}

public func run(_ name: String, _ inArgs: @autoclosure @escaping MFunc, _ outArgs: @autoclosure @escaping MLFunc = [], res: ResFunc? = nil) -> Stmt {
    Stmt.run(name, inArgs, outArgs, res)
}

// Alternative name for run
public func doRun(_ name: String, _ inArgs: @autoclosure @escaping MFunc, _ outArgs: @autoclosure @escaping MLFunc = [], res: ResFunc? = nil) -> Stmt {
    run(name, inArgs(), outArgs(), res: res)
}

public func cobegin(@TrailBuilder builder: () -> [Trail]) -> Stmt {
    Stmt.cobegin(builder())
}

public func strong(@StmtBuilder builder: () -> [Stmt]) -> Trail {
    Trail.strong(builder())
}

public func weak(@StmtBuilder builder: () -> [Stmt]) -> Trail {
    Trail.weak(builder())
}

public func whileRepeat(_ cond: @autoclosure @escaping Cond, @StmtBuilder builder: () -> [Stmt]) -> Stmt {
    when (cond()) {
        repeatUntil(builder, !cond())
        nop
    }
}

public func `repeat`(@StmtBuilder builder: () -> [Stmt]) -> Stmt {
    return repeatUntil(builder, false)
}

public func repeatUntil(@StmtBuilder _ builder: () -> [Stmt], _ cond: @autoclosure @escaping Cond) -> Stmt {
    return Stmt.repeatUntil(builder(), cond)
}

// Begin alternaive names for repeat.
public func whileLoop(_ cond: @autoclosure @escaping Cond, @StmtBuilder builder: () -> [Stmt]) -> Stmt {
    whileRepeat(cond(), builder: builder)
}

public func loop(@StmtBuilder builder: () -> [Stmt]) -> Stmt {
    `repeat`(builder: builder)
}

public func loopUntil(@StmtBuilder _ builder: () -> [Stmt], _ cond: @autoclosure @escaping Cond) -> Stmt {
    repeatUntil(builder, cond())
}
// End alternative names.

public func whenAbort(_ cond: @autoclosure @escaping Cond, @StmtBuilder builder: () -> [Stmt]) -> Stmt {
    Stmt.whenAbort(cond, builder())
}

public func match(@ConditionalBuilder builder: () -> [Conditional]) -> Stmt {
    Stmt.match(builder())
}

public func cond(_ cond: @autoclosure @escaping Cond, @StmtBuilder builder: () -> [Stmt]) -> Conditional {
    (cond, builder())
}

public func when(_ cond: @autoclosure @escaping Cond, @StmtBuilder builder: () -> [Stmt]) -> Stmt {
    Stmt.match([(cond, builder())])
}

public func exec(_ proc: @escaping Proc) -> Stmt {
    Stmt.exec(proc)
}

public func exit(_ f: @escaping Func) -> Stmt {
    Stmt.exit(f)
}

public let nop = Stmt.nop

public let noAct = activity ("__NoAct", []) { _ in
    nop
    nop
}

public func activity(_ name: String, _ inParams: [String], _ outParams: [String] = [], @StmtBuilder _ builder: @escaping (Ctx) -> [Stmt]) -> Activity
{
    return Activity(name: name, inParams: inParams, outParams: outParams, builder: builder)
}

public class Module {
    public typealias Import = Module
    
    let activities: [Activity]
    let imports: [Import]
    
    public init(imports: [Import] = [], @ActivityBuilder builder: (ID) -> [Activity]) {
        activities = builder(ID())
        self.imports = imports
    }

    subscript (name: String) -> Activity? {
        if let res = activities.first(where: { $0.name == name }) {
            return res
        }
        for m in imports {
            if let res = m[name] {
                return res
            }
        }
        return nil
    }
}

public enum TickResult {
    case wait
    case done
    case result(Any?)
}

extension TickResult : Equatable {
    public static func == (lhs: TickResult, rhs: TickResult) -> Bool {
        switch (lhs, rhs) {
        case (.wait, .wait): return true
        case (.done, .done): return true
        case (.result(_), .result(_)): return true
        default: return false
        }
    }
}

public protocol Receiver : class {
    var box: Any? { get set }

    func postValue(_ val: Any)
    func postDone()
    func react()
}

public struct ReceiveCtx {
    let queue: DispatchQueue
    let trigger: Proc
}

class ProcessorCtx {
    let module: Module
    var receiveCtx: ReceiveCtx?
    
    init(module: Module) {
        self.module = module
    }
}

public class Processor {
    let procCtx: ProcessorCtx
    let ap: ActivityProcessor

    public init(module: Module, entryPoint: String = "Main") throws {
        guard let a = module[entryPoint] else {
            throw Errors.activityNotFound(entryPoint)
        }
        procCtx = ProcessorCtx(module: module)
        ap = ActivityProcessor(act: a, procCtx: procCtx)
    }
    
    @discardableResult
    public func tick(_ inArgs: [Any], _ outArgs: [Loc]) throws -> TickResult {
        return try ap.tick(inArgs, outArgs)
    }
    
    var receiveCtx: ReceiveCtx? {
        get {
            return procCtx.receiveCtx
        }
        set {
            procCtx.receiveCtx = newValue
        }
    }
}

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

    let proc: Processor
    var cb: ReactCallback?
    var vars: [String: Any] = [:]
        
    public init(module: Module, entryPoint: String = "Main", inConfig: [VarConfig], inOutConfig: [VarConfig], queue: DispatchQueue = .main) throws {
        self.inConfig = inConfig
        self.inOutConfig = inOutConfig
        
        proc = try Processor(module: module, entryPoint: entryPoint)
        proc.receiveCtx = ReceiveCtx(queue: queue) {
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
        
        for cfg in inConfig + inOutConfig {
            vars[cfg.name] = cfg.value
        }
    }
    
    public subscript(dynamicMember name: String) -> Any {
        get {
            return vars[name]!
        }
        set {
            vars[name] = newValue
        }
    }
    
    public func react() {
        proc.receiveCtx?.trigger()
    }
    
    public var reactCallback: ReactCallback? {
        get {
            return cb
        }
        set {
            cb = newValue
        }
    }
}

extension Module {
    public func makeProcessor(entryPoint: String = "Main") -> Processor? {
        try? Processor(module: self, entryPoint: entryPoint)
    }
}

extension Activity {
    func bindInArgs(_ inArgs: [Any], _ ctx: Ctx) {
        for (p, a) in zip(inParams, inArgs) {
            ctx[dynamicMember: p] = a
        }
    }
    func bindInOutArgs(_ outArgs: [Loc], _ ctx: Ctx) {
        for (p, l) in zip(outParams, outArgs) {
            ctx[dynamicMember: p] = l.val
        }
    }
    func bindOutArgs(_ outArgs: [Loc], _ ctx: Ctx) {
        for (p, var l) in zip(outParams, outArgs) {
            l.val = ctx[dynamicMember: p]
        }
    }
}

class ActivityProcessor {
    let act: Activity
    let bp: BlockProcessor
    let ctx = Ctx()
    
    init(act: Activity, procCtx: ProcessorCtx) {
        self.act = act
        bp = BlockProcessor(stmts: act.makeStmts(ctx), procCtx: procCtx)
    }
    
    func tick(_ inArgs: [Any], _ outArgs: [Loc]) throws -> TickResult {
        act.bindInArgs(inArgs, ctx)
        act.bindInOutArgs(outArgs, ctx)
        let res = try bp.tick()
        act.bindOutArgs(outArgs, ctx)
        return res
    }
}

extension Int {
    mutating func inc() {
        self = self + 1
    }
}

class BlockProcessor {
    let stmts: [Stmt]
    let procCtx: ProcessorCtx
    var pc: Int = 0
    
    var subProc: Any?
    
    init(stmts: [Stmt], procCtx: ProcessorCtx) {
        self.stmts = stmts
        self.procCtx = procCtx
    }
    
    func reset() {
        pc = 0
    }
    
    func tick() throws -> TickResult {
        while pc < stmts.count {
            switch stmts[pc] {
                
            case .await(let c):
                if subProc == nil {
                    subProc = AwaitProcessor(cond: c)
                }
                let res = (subProc as! AwaitProcessor).tick()
                if res == .wait {
                    return res
                }
                assert(res == .done)
                subProc = nil
                pc.inc()
                
            case let .receive(outLoc, resetValue, pFunc):
                if subProc == nil {
                    subProc = ReceiveProcessor(outLoc: outLoc(), resetValue: resetValue, pFunc: pFunc, procCtx: procCtx)
                }
                let res = (subProc as! ReceiveProcessor).tick()
                if res == .wait {
                    return res
                }
                assert(res == .done)
                subProc = nil
                pc.inc()
                
            case let .run(a, inArgs, outArgs, resFunc):
                guard let act = procCtx.module[a] else {
                    throw Errors.activityNotFound(a)
                }
                if subProc == nil {
                    subProc = ActivityProcessor(act: act, procCtx: procCtx)
                }
                let res = try (subProc as! ActivityProcessor).tick(inArgs(), outArgs())
                if res == .wait {
                    return res
                }
                if let resFunc = resFunc, case .result(let val) = res {
                    resFunc(val)
                }
                subProc = nil
                pc.inc()

            case let .repeatUntil(ss, c):
                if subProc == nil {
                    subProc = WhileProcessor(cond: c, stmts: ss, procCtx: procCtx)
                }
                let res = try (subProc as! WhileProcessor).tick()
                if res == .wait {
                    return res
                }
                subProc = nil
                if res == .done {
                    pc.inc()
                } else {
                    return res
                }

            case let .cobegin(ts):
                if subProc == nil {
                    subProc = CobeginProcessor(trails: ts, procCtx: procCtx)
                }
                let res = try (subProc as! CobeginProcessor).tick()
                if res == .wait {
                    return res
                }
                assert(res == .done)
                subProc = nil
                pc.inc()

            case let .match(conds):
                if subProc == nil {
                    subProc = MatchProcessor(conds: conds, procCtx: procCtx)
                }
                let res = try (subProc as! MatchProcessor).tick()
                if res == .wait {
                    return res
                }
                subProc = nil
                if res == .done {
                    pc.inc()
                } else {
                    return res
                }

            case let .whenAbort(cond, stmts):
                if subProc == nil {
                    subProc = AbortProcessor(cond: cond, stmts: stmts, procCtx: procCtx)
                }
                let res = try (subProc as! AbortProcessor).tick()
                if res == .wait {
                    return res
                }
                subProc = nil
                if res == .done {
                    pc.inc()
                } else {
                    return res
                }

            case .exec(let p):
                p()
                pc.inc()
                
            case .exit(let f):
                return .result(f())

            case .nop:
                pc.inc()
            }
        }
        return .done
    }
}

class AwaitProcessor {
    let c: Cond
    var hitAwait = true
    
    init(cond: @escaping Cond) {
        c = cond
    }
    
    func tick() -> TickResult {
        guard !hitAwait else {
            hitAwait = false
            return .wait
        }
        return c() ? .done : .wait
    }
}

class ReceiveProcessor : Receiver {    
    var outLoc: Loc
    let resetValue: Any?
    let procCtx: ProcessorCtx
    var val: Any?
    var res: TickResult = .wait
    var box: Any?

    init(outLoc: Loc, resetValue: Any?, pFunc: PFunc, procCtx: ProcessorCtx) {
        self.outLoc = outLoc
        self.resetValue = resetValue
        self.procCtx = procCtx
        pFunc(self)
    }
    
    func tick() -> TickResult {
        if let val = val {
            outLoc.val = val
            self.val = nil
        } else {
            if let resetVal = resetValue {
                outLoc.val = resetVal
            }
        }
        return res
    }
    
    func postValue(_ val: Any) {
        procCtx.receiveCtx?.queue.async {
            self.val = val
        }
    }
    
    func postDone() {
        procCtx.receiveCtx?.queue.async {
            self.res = .done
        }
    }
    
    func react() {
        procCtx.receiveCtx?.queue.async {
            self.procCtx.receiveCtx?.trigger()
        }
    }
}

class CobeginProcessor {
    let tps: [TrailProcessor]
    
    init(trails: [Trail], procCtx: ProcessorCtx) {
        tps = trails.map { trail in
            switch trail {
            case .strong(let ss):
                return TrailProcessor(stmts: ss, procCtx: procCtx, strong: true)
            case .weak(let ss):
                return TrailProcessor(stmts: ss, procCtx: procCtx, strong: false)
            }
        }
    }
    
    func tick() throws -> TickResult {
        var doneStrong = 0
        var doneWeak = 0
        var numStrong = 0
        
        for tp in tps {
            let res = try tp.tick()
            if res == .done {
                if tp.strong {
                    doneStrong += 1
                } else {
                    doneWeak += 1
                }
            }
            else if res != .wait {
                throw Errors.exitNotAllowed
            }
            if tp.strong {
                numStrong += 1
            }
        }
        return (doneStrong == numStrong && numStrong > 0) || (doneWeak > 0 && numStrong == 0) ? .done : .wait
    }
}

class TrailProcessor : BlockProcessor {
    let strong: Bool
    
    init(stmts: [Stmt], procCtx: ProcessorCtx, strong: Bool) {
        self.strong = strong
        super.init(stmts: stmts, procCtx: procCtx)
    }
}

class WhileProcessor {
    let c: Cond
    let bp: BlockProcessor
    
    init(cond: @escaping Cond, stmts: [Stmt], procCtx: ProcessorCtx) {
        c = cond
        bp = BlockProcessor(stmts: stmts, procCtx: procCtx)
    }
    
    func tick() throws -> TickResult {
        while true {
            let res = try bp.tick()
            if res != .done {
                return res
            }
            if c() {
                return .done
            }
            bp.reset()
        }
    }
}

class AbortProcessor {
    let c: Cond
    let bp: BlockProcessor
    var check = false
    
    init(cond: @escaping Cond, stmts: [Stmt], procCtx: ProcessorCtx) {
        c = cond
        bp = BlockProcessor(stmts: stmts, procCtx: procCtx)
    }
    
    func tick() throws -> TickResult {
        if check {
            if c() {
                return .done
            }
        }
        let res = try bp.tick()
        check = true
        return res
    }
}

class MatchProcessor {
    let bp: BlockProcessor?
    
    init(conds: [Conditional], procCtx: ProcessorCtx) {
        for (cond, stmts) in conds {
            if cond() {
                bp = BlockProcessor(stmts: stmts, procCtx: procCtx)
                return
            }
        }
        bp = nil
    }
    
    func tick() throws -> TickResult {
        guard let bp = bp else {
            return .done
        }
        return try bp.tick()
    }
}

// MARK: - Combine extensions

@available(OSX 10.15, *)
public extension Reactor {
    func publisher(for v: String) -> AnyPublisher<Any, Never> {
        let res = PassthroughSubject<Any, Never>()
        let oldCB = reactCallback
        reactCallback = { tr in
            oldCB?(tr)
            res.send(self[dynamicMember: v])
            switch tr {
            case .done, .result(_):
                res.send(completion: .finished)
            default:
                break
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
public extension Publisher {
    func eraseTotally() -> AnyPublisher<Any, Self.Failure> {
        self.map { $0 as Any }.eraseToAnyPublisher()
    }
}

// MARK: - Standard Modules

@available(OSX 10.15, *)
public let clockModule = Module { name in
    activity (name.Clock, [name.interval, name.shouldReact]) { val in
        exec { val.tick = false }
        receive (val.loc.tick, resetTo: false, reactOnValue: val.shouldReact as Bool) {
            Timer.publish(every: val.interval, on: .main, in: .default).autoconnect().map { _ in return true }.eraseToAnyPublisher()
        }
    }
    noAct
}
