// Project Pappe
// Copyright 2020, Framework Labs.

import Dispatch

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
    case select([Match])
    case exec(Proc)
    case `defer`(Proc)
    case exit(Func)
}

public enum Trail {
    case strong([Stmt])
    case weak([Stmt])
}

public typealias Match = (Cond, [Stmt])

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
public struct MatchBuilder {
    public static func buildBlock(_ matches: Match...) -> [Match] {
        return matches
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

public func run(_ name: String, _ inArgs: @autoclosure @escaping MFunc, _ outArgs: @autoclosure @escaping MLFunc = [], _ res: ResFunc? = nil) -> Stmt {
    Stmt.run(name, inArgs, outArgs, res)
}

public func cobegin(@TrailBuilder _ builder: () -> [Trail]) -> Stmt {
    Stmt.cobegin(builder())
}

public func strong(@StmtBuilder _ builder: () -> [Stmt]) -> Trail {
    Trail.strong(builder())
}

public func weak(@StmtBuilder _ builder: () -> [Stmt]) -> Trail {
    Trail.weak(builder())
}

public func `while`(_ cond: @escaping Cond, @StmtBuilder repeat builder: () -> [Stmt]) -> Stmt {
    `if` { cond() } then: {
        `repeat`(builder, until: {!cond()})
    }
}

public func `repeat`(@StmtBuilder _ builder: () -> [Stmt]) -> Stmt {
    return Stmt.repeatUntil(builder(), { false })
}

public func `repeat`(@StmtBuilder _ builder: () -> [Stmt], until cond: @escaping Cond) -> Stmt {
    return Stmt.repeatUntil(builder(), cond)
}

public func when(_ cond: @escaping Cond, @StmtBuilder abort builder: () -> [Stmt]) -> Stmt {
    Stmt.whenAbort(cond, builder())
}

public func select(@MatchBuilder _ builder: () -> [Match]) -> Stmt {
    Stmt.select(builder())
}

public func match(_ cond: @escaping Cond, @StmtBuilder then builder: () -> [Stmt]) -> Match {
    (cond, builder())
}

public func otherwise(@StmtBuilder _ builder: () -> [Stmt]) -> Match {
    ({ true }, builder())
}

public func `if`(_ cond: @escaping Cond, @StmtBuilder then builder: () -> [Stmt]) -> Stmt {
    Stmt.select([(cond, builder())])
}

public func `if`(_ cond: @escaping Cond, @StmtBuilder then builder: () -> [Stmt], @StmtBuilder else altBuilder: () -> [Stmt]) -> Stmt {
    Stmt.select([
        (cond, builder()),
        ({ true }, altBuilder())
    ])
}

public func exec(_ proc: @escaping Proc) -> Stmt {
    Stmt.exec(proc)
}

public func `defer`(_ proc: @escaping Proc) -> Stmt {
    Stmt.`defer`(proc)
}

public func exit(_ f: @escaping Func) -> Stmt {
    Stmt.exit(f)
}

public func activity(_ name: String, _ inParams: [String], _ outParams: [String] = [], @StmtBuilder _ builder: @escaping (Ctx) -> [Stmt]) -> Activity
{
    return Activity(name: name, inParams: inParams, outParams: outParams, builder: builder)
}

@available(swift 5.3)
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
    var deferedProcs: [Proc] = []
    
    init(stmts: [Stmt], procCtx: ProcessorCtx) {
        self.stmts = stmts
        self.procCtx = procCtx
    }
    
    deinit {
        for proc in deferedProcs {
            proc()
        }
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

            case let .select(matches):
                if subProc == nil {
                    subProc = MatchProcessor(matches: matches, procCtx: procCtx)
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
                
            case .defer(let p):
                deferedProcs.append(p)
                pc.inc()
                
            case .exit(let f):
                return .result(f())
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
    
    init(matches: [Match], procCtx: ProcessorCtx) {
        for (cond, stmts) in matches {
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
