// Project Pappe
// Copyright 2020-2021, Framework Labs.

import Dispatch

/// A list of possible runtime errors.
public enum Errors : Error {
    case varNotFound(String)
    case activityNotFound(String)
    case returnNotAllowed
}

/// Protocol for the location of a variable.
public protocol Loc {
    
    /// Get and set the value of the variable at this location.
    var val: Any { get set }
}

/// Concrete location which directly stores the value.
public class DirectLoc : Loc {
    public var val: Any
    public init(val: Any) {
        self.val = val
    }
}

struct CtxLoc : Loc {
    let name: String
    unowned let ctx: Ctx
    
    var val: Any {
        get {
            ctx[dynamicMember: name]
        }
        set {
            ctx[dynamicMember: name] = newValue
        }
    }
}

/// Creates a location for a given variable name.
@dynamicMemberLookup
public struct Locs {
    unowned let ctx: Ctx
    
    /// Creates the location from a variable name given by member lookup.
    public subscript(dynamicMember name: String) -> Loc {
        CtxLoc(name: name, ctx: ctx)
    }
}

/// Stores the previous values of the context variables for read only.
@dynamicMemberLookup
public class PrevCtx
{
    var map: [String: Any] = [:]

    /// Get a variable by member lookup.
    public subscript<T>(dynamicMember name: String) -> T {
        if let val = map[name] {
            return val as! T
        }
        fatalError("\(name) is not a variable!")
    }
    
    /// Get a variable or a fallback value by subscript: `val.prev[name.x, or: 0]`.
    public subscript<T>(_ name: String, or defaultVal: T) -> T {
        if let val = map[name] {
            return val as! T
        } else {
            return defaultVal
        }
    }
}

/// Stores local variables like in Python.
@dynamicMemberLookup
public class Ctx {
    private var map: [String: Any] = [:]
    private var presencables: [Presencable] = []
    private let semaphore = DispatchSemaphore(value: 1)
    
    /// Access to the location factory.
    public lazy var loc: Locs = Locs(ctx: self)
    
    /// Access to the previous context values.
    public let prev: PrevCtx = PrevCtx();
            
    /// Get and set a variable by member lookup.
    public subscript<T>(dynamicMember name: String) -> T {
        get {
            synchronized {
                if let val = map[name] {
                    return val as! T
                }
                fatalError("\(name) is not a variable!")
            }
        }
        set {
            synchronized {
                map[name] = newValue
                if let presencable = newValue as? Presencable {
                    presencables.append(presencable)
                }
            }
        }
    }
    
    func setPrevFromNow() {
        synchronized {
            prev.map = map
        }
    }
    
    func makeAbsent() {
        synchronized {
            for presencable in presencables {
                presencable.makeAbsent()
            }
        }
    }

    private func synchronized<T>(_ f: () -> T) -> T {
        semaphore.wait()
        defer { semaphore.signal() }
        return f()
    }
}

/// Types adopting this protocol have a state  of being  present or absent.
///
/// On every tick start, objects with this marker will be made absent again.
public protocol Presencable : AnyObject {
    var isPresent: Bool { get }
    func makeAbsent()
}

/// A simple boolean signal which is either present or absent.
public class Signal : Presencable {
    public private(set) var isPresent = false
    
    /// Emits the signal thus making it present.
    public func emit() {
        isPresent = true
    }
    
    public func makeAbsent() {
        isPresent = false
    }
}

/// A signal which bears a value and is in addition either present or absent.
public class ValueSignal<T> : Presencable {
    public private(set) var isPresent = false
    
    /// Access to the emitted value.
    public private(set) var val: T?
    
    /// Emits the signal with the given value thus making it present.
    public func emit(_ val: T) {
        self.val = val
        isPresent = true
    }
    
    public func makeAbsent() {
        isPresent = false
    }
}

/// Helper which asks the presence status of an object retrieved from a context.
public func present(_ presencable: Presencable) -> Bool {
    return presencable.isPresent
}

/// Helper which calls emit() on a signal retrieved from a context.
public func emit(_ sig: Signal) {
    sig.emit()
}

/// Helper which calls emit() with a value on a signal retrieved from a context.
public func emit<T>(_ sig: ValueSignal<T>, with val: T) {
    sig.emit(val)
}

/// Helper which returns the value stored in a `ValueSignal`retrieved from a context.
public func emittedValue<T>(_ sig: ValueSignal<T>, as ty: T.Type) -> T? {
    sig.val
}

/// Converts a member-lookup into a string.
@dynamicMemberLookup
public struct ID {
    
    /// Returns the string for the given member lookup.
    public subscript(dynamicMember name: String) -> String {
        name
    }
}

public typealias Proc = () -> Void
public typealias Func = () -> Any
public typealias LFunc = () -> Loc
public typealias SFunc = () -> String
public typealias PFunc = (Receiver) -> Void
public typealias MFunc = () -> [Any]
public typealias MLFunc = () -> [Loc]
public typealias Cond = () -> Bool
public typealias ResFunc = (Any?) -> Void

let trueCond: Cond = { true }
let falseCond: Cond = { false }

public enum Stmt {
    case await(Cond)
    case receive(LFunc, Any?, PFunc)
    case run(SFunc, MFunc, MLFunc, ResFunc?)
    case cobegin([Trail], parallel: Bool)
    case repeatUntil([Stmt], Cond)
    case when(WhenType, Cond, [Stmt])
    case select([Match])
    case exec(Proc)
    case `defer`(Proc)
    case exit(Func)
}

public enum WhenType {
    case abort
    case suspend
}

/// Options for a trail.
public struct TrailOptions : OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// Mark this trail as weak - it will be strong otherwise.
    public static let weak = TrailOptions(rawValue: 1)

    /// Marks this trail as prarallel - will be scope defined otherwise.
    public static let parallel = TrailOptions(rawValue: 2)
}

public struct Trail {
    let opts: TrailOptions
    let stmts: [Stmt]
}

public typealias Match = (Cond, [Stmt])

public struct Activity {
    let name: String
    private let inParams: [String]
    private let outParams: [String]
    private let builder: (Ctx) -> [Stmt]
    
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

@resultBuilder
public struct StmtBuilder {
    public static func buildBlock(_ stmts: Stmt...) -> [Stmt] {
        stmts
    }
}

@resultBuilder
public struct TrailBuilder {
    public static func buildBlock(_ trails: Trail...) -> [Trail] {
        trails
    }
}

@resultBuilder
public struct MatchBuilder {
    public static func buildBlock(_ matches: Match...) -> [Match] {
        matches
    }
}

@resultBuilder
public struct ActivityBuilder {
    public static func buildBlock(_ acts: Activity...) -> [Activity] {
        acts
    }
}

/// Waits for the next step. At the beginning of the next step `cond` is checked and if `true` control progresses else it waits for the next step.
public func await(_ cond: @escaping Cond) -> Stmt {
    Stmt.await(cond)
}

/// 'Unofficial' statement to wait until an asynchronous function calls back on the `Receiver` passed to the closure.
public func receive(_ outArg: @autoclosure @escaping LFunc, resetTo value: Any? = nil, _ pfun: @escaping PFunc) -> Stmt {
    Stmt.receive(outArg, value, pfun)
}

/// Runs the activity with the given `name` passing `inArgs` and `outArgs` to/from it in every step. When the activity ends, a result might be passed in the final closure.
public func run(_ name: @autoclosure @escaping SFunc, _ inArgs: @autoclosure @escaping MFunc, _ outArgs: @autoclosure @escaping MLFunc = [], _ res: ResFunc? = nil) -> Stmt {
    Stmt.run(name, inArgs, outArgs, res)
}

/// Begins scope of concurrent trails.
public func cobegin(@TrailBuilder _ builder: () -> [Trail]) -> Stmt {
    Stmt.cobegin(builder(), parallel: false)
}

/// Begins scope of parallel trails.
public func parbegin(@TrailBuilder _ builder: () -> [Trail]) -> Stmt {
    Stmt.cobegin(builder(), parallel: true)
}

/// A trail with the specified options like `.weak` or `.parallel`.
public func with(_ opts: TrailOptions = [], @StmtBuilder _ builder: () -> [Stmt]) -> Trail {
    Trail(opts: opts, stmts: builder())
}

/// A trail which will determine the life-cycle of a `cobegin` statement.
@available(*, deprecated, renamed: "with")
public func strong(@StmtBuilder _ builder: () -> [Stmt]) -> Trail {
    Trail(opts: [], stmts: builder())
}

/// A trail which can be preempted at the end of a step if all strong trails have finished.
@available(*, deprecated, message: "use `with (.weak)` instead")
public func weak(@StmtBuilder _ builder: () -> [Stmt]) -> Trail {
    Trail(opts: .weak, stmts: builder())
}

/// Checks `cond` at the beginning of each  loop and enters it if `true`.
public func `while`(_ cond: @escaping Cond, @StmtBuilder repeat builder: () -> [Stmt]) -> Stmt {
    Stmt.select([(cond, [Stmt.repeatUntil(builder(), { !cond() })])])
}

/// Unconditionally repeats the statements in the body.
public func `repeat`(@StmtBuilder _ builder: () -> [Stmt]) -> Stmt {
    Stmt.repeatUntil(builder(), falseCond)
}

/// Checks `cond` at the and of each loop and stops looping once it becomes `true`.
public func `repeat`(@StmtBuilder _ builder: () -> [Stmt], until cond: @escaping Cond) -> Stmt {
    Stmt.repeatUntil(builder(), cond)
}

/// Checks `cond` on every step and aborts the body if `true`.
public func when(_ cond: @escaping Cond, @StmtBuilder abort builder: () -> [Stmt]) -> Stmt {
    Stmt.when(.abort, cond, builder())
}

/// Checks `cond` on every step and restarts the body if `true`.
public func when(_ cond: @escaping Cond, @StmtBuilder reset builder: () -> [Stmt]) -> Stmt {
    var done = false
    return `repeat` {
        Stmt.when(.abort, cond, builder() + [exec { done = true }])
    } until: { done }
}

/// Checks `cond` on every step and suspends the body if `true`.
public func when(_ cond: @escaping Cond, @StmtBuilder suspend builder: () -> [Stmt]) -> Stmt {
    Stmt.when(.suspend, cond, builder())
}

/// Runs the statements of the first match with a `true` condition.
public func select(@MatchBuilder _ builder: () -> [Match]) -> Stmt {
    Stmt.select(builder())
}

/// Statements guarded by the condition `cond`.
public func match(_ cond: @escaping Cond, @StmtBuilder then builder: () -> [Stmt]) -> Match {
    (cond, builder())
}

/// Statements which are always able to run.
public func otherwise(@StmtBuilder _ builder: () -> [Stmt]) -> Match {
    (trueCond, builder())
}

/// Runs statements conditionally.
public func `if`(_ cond: @escaping Cond, @StmtBuilder then builder: () -> [Stmt]) -> Stmt {
    Stmt.select([(cond, builder())])
}

/// Runs statements conditionally with an alternative if `cond` evaluates to `false`.
public func `if`(_ cond: @escaping Cond, @StmtBuilder then builder: () -> [Stmt], @StmtBuilder else altBuilder: () -> [Stmt]) -> Stmt {
    Stmt.select([
        (cond, builder()),
        (trueCond, altBuilder())
    ])
}

/// Executes arbitrary one-step code.
public func exec(_ proc: @escaping Proc) -> Stmt {
    Stmt.exec(proc)
}

/// One-step code which runs when the scope is left.
///
/// Contrary to local variables, which have the activity as scope (like in Python), the scope of a `defer` corresponds to statement blocks like the body of a `repeat`.
public func `defer`(_ proc: @escaping Proc) -> Stmt {
    Stmt.`defer`(proc)
}

/// Returns from an activity by returning the result of the given function.
public func `return`(_ f: @escaping Func) -> Stmt {
    Stmt.exit(f)
}

/// 'Unofficial' statement which waits for `cond` to be true before executing given one-step code; then it repeats.
public func every(_ cond: @escaping Cond, do proc: @escaping Proc) -> Stmt {
    Stmt.repeatUntil([Stmt.await(cond), Stmt.exec(proc)], falseCond)
}

/// 'Unofficial' statement which executes given one-step code before it waits for `cond` to be true; then it repeats.
public func nowAndEvery(_ cond: @escaping Cond, do proc: @escaping Proc) -> Stmt {
    Stmt.repeatUntil([Stmt.exec(proc), Stmt.await(cond)], falseCond)
}

/// 'Unofficial'' statement which executes given one-step code now and every following step.
public func always(_ proc: @escaping Proc) -> Stmt {
    Stmt.repeatUntil([Stmt.exec(proc), Stmt.await(trueCond)], falseCond)
}

/// Emits the specified `Signal` on every tick.
public func sustain(_ sig: @escaping () -> Signal) -> Stmt {
    always {
        emit(sig())
    }
}

/// Emits the specified `ValueSignal` with the given value on every tick.
public func sustain<T>(_ sig: @escaping () -> ValueSignal<T>, with val: @escaping () -> T) -> Stmt {
    always {
        emit(sig(), with: val())
    }
}

/// 'Unofficial'' statement which pauses until the next step. Equivalent to `await { true }`.
public let pause = `await` { true }

/// 'Unofficial'' statement which pauses indefinitely. Equivalent to `await { false }`.
public let halt = `await` { false }

/// Definition of a new activity with name, input and in-out parameters.
public func activity(_ name: String, _ inParams: [String], _ outParams: [String] = [], @StmtBuilder _ builder: @escaping (Ctx) -> [Stmt]) -> Activity
{
    Activity(name: name, inParams: inParams, outParams: outParams, builder: builder)
}

/// A collection of activities.
@available(swift 5.3)
public class Module {
    public typealias Import = Module
    
    private let activities: [Activity]
    private let imports: [Import]
    
    /// Creates a module.
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

/// The result of a tick().
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

/// Callback interface called by asynchronous functions once they are ready.
public protocol Receiver : AnyObject {
    var box: Any? { get set }

    func postValue(_ val: Any)
    func postDone()
    func react()
}

/// Provides information what to do when an async function calls back on `Receive`.
public struct ReceiveCtx {
    public init(queue: DispatchQueue, trigger: @escaping Proc) {
        self.queue = queue
        self.trigger = trigger
    }
    public let queue: DispatchQueue
    public let trigger: Proc
}

class ProcessorCtx {
    let module: Module
    var receiveCtx: ReceiveCtx?
    
    init(module: Module) {
        self.module = module
    }
}

/// Runs activities step by step.
public class Processor {
    private let procCtx: ProcessorCtx
    private var ap: ActivityProcessor?

    /// Creates a processor with given `module` and `entryPoint`.
    public init(module: Module, entryPoint: String = "Main") throws {
        guard let a = module[entryPoint] else {
            throw Errors.activityNotFound(entryPoint)
        }
        procCtx = ProcessorCtx(module: module)
        ap = ActivityProcessor(act: a, procCtx: procCtx)
    }
    
    /// Runs a single step with given input and in-out arguments.
    @discardableResult
    public func tick(_ inArgs: [Any], _ outArgs: [Loc]) throws -> TickResult {
        guard let ap = ap else { return .done }
        let res = try ap.tick(inArgs, outArgs)
        if res != .wait {
            self.ap = nil
        }
        return res
    }
    
    /// Allows to get and set the `ReceiverCtx`.
    public var receiveCtx: ReceiveCtx? {
        get {
            procCtx.receiveCtx
        }
        set {
            procCtx.receiveCtx = newValue
        }
    }
}

extension Module {
    
    /// Helper to get a processor from a `Module`.
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
    private let act: Activity
    private let bp: BlockProcessor
    private let ctx = Ctx()
    
    init(act: Activity, procCtx: ProcessorCtx) {
        self.act = act
        bp = BlockProcessor(stmts: act.makeStmts(ctx), procCtx: procCtx)
    }
    
    func tick(_ inArgs: [Any], _ outArgs: [Loc]) throws -> TickResult {
        ctx.setPrevFromNow()
        ctx.makeAbsent()
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
    private let stmts: [Stmt]
    private let procCtx: ProcessorCtx
    private var pc: Int = 0
    private var subProc: Any?
    private var deferedProcs: [Proc] = []
    
    init(stmts: [Stmt], procCtx: ProcessorCtx) {
        self.stmts = stmts
        self.procCtx = procCtx
    }
    
    deinit {
        // Clear subProc first so that inner defers also run first!
        subProc = nil
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
                if subProc == nil {
                    let name = a()
                    guard let act = procCtx.module[name] else {
                        throw Errors.activityNotFound(name)
                    }
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

            case let .cobegin(ts, isParallel):
                if subProc == nil {
                    subProc = CobeginProcessor(trails: ts, isParallel: isParallel, procCtx: procCtx)
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

            case let .when(type, cond, stmts):
                if subProc == nil {
                    subProc = WhenProcessor(type: type, cond: cond, stmts: stmts, procCtx: procCtx)
                }
                let res = try (subProc as! WhenProcessor).tick()
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
    private let c: Cond
    private var hitAwait = true
    
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
    private var outLoc: Loc
    private let resetValue: Any?
    private let procCtx: ProcessorCtx
    private var val: Any?
    private var res: TickResult = .wait
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
    private let tps: [TrailProcessor]
    private let isParallel: Bool
    
    class ParRes {
        let isStrong: Bool
        var res: TickResult? = nil

        init(_ isStrong: Bool) {
            self.isStrong = isStrong
        }
    }
    private var parResults = [ParRes]()
    
    private let group = DispatchGroup()
    
    init(trails: [Trail], isParallel: Bool, procCtx: ProcessorCtx) {
        tps = trails.map { trail in
            return TrailProcessor(opts: trail.opts, stmts: trail.stmts, procCtx: procCtx)
        }
        self.isParallel = isParallel
    }
    
    func tick() throws -> TickResult {
        var doneStrong = 0
        var doneWeak = 0
        var numStrong = 0
        
        func updateStats(res: TickResult, isStrong: Bool) throws {
            if res == .done {
                if isStrong {
                    doneStrong += 1
                } else {
                    doneWeak += 1
                }
            }
            else if res != .wait {
                throw Errors.returnNotAllowed
            }
            if isStrong {
                numStrong += 1
            }
        }
        
        let queue = DispatchQueue.global()
        var parMode = false
        var firstParTrailProc: TrailProcessor?
        
        func finishParMode() throws {
            guard parMode else { return }
            
            if let tp = firstParTrailProc {
                let res = try tp.tick()
                try updateStats(res: res, isStrong: tp.strong)
                firstParTrailProc = nil
            }
            group.wait()
            parMode = false
        }
        
        for tp in tps {
            if isParallel || tp.parallel {
                if !parMode {
                    firstParTrailProc = tp
                }
                else {
                    let parRes = ParRes(tp.strong)
                    parResults.append(parRes)
                    
                    queue.async(group: group) { [unowned parRes, unowned tp] in
                        parRes.res = try! tp.tick()
                    }
                }
                parMode = true
            }
            else {
                try finishParMode()
                let res = try tp.tick()
                try updateStats(res: res, isStrong: tp.strong)
            }
        }
        try finishParMode()
        
        for parRes in parResults {
            try updateStats(res: parRes.res!, isStrong: parRes.isStrong)
        }
        parResults.removeAll(keepingCapacity: true)

        return (doneStrong == numStrong && numStrong > 0) || (doneWeak > 0 && numStrong == 0) ? .done : .wait
    }
}

class TrailProcessor : BlockProcessor {
    let opts: TrailOptions
    var strong: Bool {
        return !opts.contains(.weak)
    }
    var parallel: Bool {
        return opts.contains(.parallel)
    }
    
    init(opts: TrailOptions, stmts: [Stmt], procCtx: ProcessorCtx) {
        self.opts = opts
        super.init(stmts: stmts, procCtx: procCtx)
    }
}

class WhileProcessor {
    private let c: Cond
    private let bp: BlockProcessor
    
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

class WhenProcessor {
    private let t: WhenType
    private let c: Cond
    private let bp: BlockProcessor
    private var check = false
    
    init(type: WhenType, cond: @escaping Cond, stmts: [Stmt], procCtx: ProcessorCtx) {
        t = type
        c = cond
        bp = BlockProcessor(stmts: stmts, procCtx: procCtx)
    }
    
    func tick() throws -> TickResult {
        if check {
            if c() {
                switch t {
                case .abort:
                    return .done
                case .suspend:
                    return .wait
                }
            }
        }
        let res = try bp.tick()
        check = true
        return res
    }
}

class MatchProcessor {
    private let bp: BlockProcessor?
    
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
