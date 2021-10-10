import XCTest
@testable import Pappe

extension Module {
    func test(steps: Int) {
        do {
            let p = try Processor(module: self)
            for _ in 0..<steps {
                try p.tick([], [])
            }
        } catch {
            XCTFail("failed due to exception: \(error)")
        }
    }
}

final class PappeTests: XCTestCase {
    
    let common = Module { name in
        activity (name.Delay, [name.ticks]) { val in
            exec { val.i = val.ticks as Int }
            `while` { val.i > 0 } `repeat`: {
                exec { val.i -= 1 }
                pause
            }
        }
    }
    
    func testAwait() {
        Module { name in
            activity (name.Test, [name.in1, name.in2], [name.out]) { val in
                exec { val.out = false }
                `await` { val.in1 && val.in2 }
                exec { val.out = true }
            }
            activity (name.Main, []) { val in
                exec { val.out =  false }
                cobegin {
                    with {
                        exec {
                            val.in1 = false
                            val.in2 = false
                            val.expect = false
                        }
                        pause
                        exec {
                            val.in1 = true
                            val.in2 = false
                            val.expect = false
                        }
                        pause
                        exec {
                            val.in1 = false
                            val.in2 = true
                            val.expect = false
                        }
                        pause
                        exec {
                            val.in1 = true
                            val.in2 = true
                            val.expect = true
                        }
                    }
                    with (.weak) {
                        Pappe.run (name.Test, [val.in1, val.in2], [val.loc.out])
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.out as Bool, val.expect)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }

    func testReturn() {
        Module { name in
            activity (name.Inner, []) { val in
                `return` { 42 }
                halt
            }
            activity (name.Test, []) { val in
                when { false } abort: {
                    `repeat` {
                        pause
                        Pappe.run  (name.Inner, []) { res in val.tmp = res }
                        `return` { val.tmp }
                        halt
                    }
                }
            }
            activity (name.Main, []) { val in
                exec { val.out = 0 }
                cobegin {
                    with {
                        exec { val.expect = 0 }
                        pause
                        exec { val.expect = 42 }
                        pause
                    }
                    with (.weak) {
                        Pappe.run  (name.Test, []) { res in val.out = res }
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.out as Int, val.expect)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }
    
    func testCobegin() {
        Module(imports: [common]) { name in
            activity (name.Test, [], [name.done]) { val in
                cobegin {
                    with {
                        Pappe.run (name.Delay, [1])
                    }
                    with {
                        Pappe.run (name.Delay, [3])
                    }
                    with {
                        Pappe.run (name.Delay, [2])
                    }
                    with (.weak) {
                        Pappe.run (name.Delay, [2])
                    }
                    with (.weak) {
                        Pappe.run (name.Delay, [4])
                    }
                }
                exec { val.done = true }
            }
            activity (name.Main, []) { val in
                exec { val.out = false }
                cobegin {
                    with {
                        exec { val.expect = false }
                        pause
                        exec { val.expect = false }
                        pause
                        exec { val.expect = false }
                        pause
                        exec { val.expect = true }
                    }
                    with (.weak) {
                        Pappe.run (name.Test, [], [val.loc.out])
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.out as Bool, val.expect)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }

    func testRepeat() {
        Module { name in
            activity (name.TestRepeatUntil, [], [name.done]) { val in
                exec { val.i = 3 }
                `repeat` {
                    exec { val.i -= 1 }
                    pause
                } until: { val.i == 0 }
                exec { val.done = true }
            }
            activity (name.TestWhileRepeat, [], [name.done]) { val in
                exec { val.i = 3 }
                `while` { val.i > 0 } repeat: {
                    exec { val.i -= 1 }
                    pause
                }
                exec { val.done = true }
            }
            activity (name.Main, []) { val in
                exec {
                    val.outRepeatUntil = false
                    val.outWhileRepeat = false
                }
                cobegin {
                    with {
                        exec { val.expect = false }
                        pause
                        exec { val.expect = false }
                        pause
                        exec { val.expect = false }
                        pause
                        exec { val.expect = true }
                    }
                    with (.weak) {
                        Pappe.run (name.TestRepeatUntil, [], [val.loc.outRepeatUntil])
                    }
                    with (.weak) {
                        Pappe.run (name.TestWhileRepeat, [], [val.loc.outWhileRepeat])
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.outRepeatUntil as Bool, val.expect)
                            XCTAssertEqual(val.outWhileRepeat as Bool, val.expect)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }
    
    func testAbort() {
        Module { name in
            activity (name.Test, [], [name.pos]) { val in
                when { true } abort: {
                    exec { val.pos = 1 }
                    pause
                    exec { val.pos = 2 }
                    pause
                }
                exec { val.pos = 3 }
            }
            activity (name.Main, []) { val in
                exec { val.out = 0 }
                cobegin {
                    with {
                        exec { val.expect = 1 }
                        pause
                        exec { val.expect = 3 }
                    }
                    with (.weak) {
                        Pappe.run (name.Test, [], [val.loc.out])
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.out as Int, val.expect)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }
    
    func testAbortPrecedence() {
        Module { name in
            activity (name.Test, [name.outer, name.inner], [name.reachedInner, name.seenOuter, name.seenInner]) { val in
                when { val.outer } abort: {
                    when { val.inner } abort: {
                        exec { val.reachedInner = true }
                        halt
                    }
                    exec { val.seenInner = true }
                    halt
                }
                exec { val.seenOuter = true }
                halt
            }
            activity (name.Main, []) { val in
                exec {
                    val.reachedInner = false
                    val.seenOuter = false
                    val.seenInner = false
                }
                cobegin {
                    with {
                        exec {
                            val.outer = false
                            val.inner = false
                            val.expectedOuter = false
                            val.expectedInner = false
                        }
                        pause
                        exec {
                            val.outer = true
                            val.inner = true
                            val.expectedOuter = true
                            val.expectedInner = false
                        }
                        pause
                    }
                    with (.weak) {
                        Pappe.run (name.Test, [val.outer, val.inner], [val.loc.reachedInner, val.loc.seenOuter, val.loc.seenInner])
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.reachedInner as Bool, true)
                            XCTAssertEqual(val.seenOuter as Bool, val.expectedOuter)
                            XCTAssertEqual(val.seenInner as Bool, val.expectedInner)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }
    
    func testReset() {
        Module { name in
            activity (name.Main, []) { val in
                cobegin {
                    with {
                        exec {
                            val.cond = false
                            val.step = 0
                            val.expectedStep = 1
                        }
                        pause
                        exec { val.expectedStep = 2 }
                        pause
                        exec { val.expectedStep = 3 }
                        pause
                        
                        exec { val.expectedStep = 1 }
                        pause
                        exec {
                            val.cond = true
                            val.expectedStep = 2
                        }
                        pause
                        exec {
                            val.cond = false
                            val.expectedStep = 12
                        }
                        pause
                        exec { val.expectedStep = 112 }
                        pause
                        
                        exec { val.expectedStep = 1 }
                        pause
                        exec {
                            val.innerCond = true
                            val.expectedStep = 2
                        }
                        pause
                        exec {
                            val.innerCond = false
                            val.expectedStep = 12
                        }
                        pause
                        exec { val.expectedStep = 112 }
                        pause
                        exec { val.expectedStep = 1112 }
                        pause
                    }
                    with (.weak) {
                        when { val.cond } reset: {
                            exec { val.step = 1 }
                            pause
                            exec { val.step = 2}
                            pause
                        }
                        exec { val.step = 3 }
                        pause
                        
                        exec { val.step = 0 }
                        when { val.cond } reset: {
                            exec { val.step = val.step + 1 }
                            pause
                            exec { val.step = val.step + 10 }
                            pause
                        }
                        exec { val.step = val.step + 100 }
                        pause
                        
                        exec { val.step = 0 }
                        when { val.cond } reset: {
                            when { val.innerCond } reset: {
                                exec { val.step = val.step + 1 }
                                pause
                                exec { val.step = val.step + 10 }
                                pause
                            }
                            exec { val.step = val.step + 100 }
                            pause
                        }
                        exec { val.step = val.step + 1000 }
                        pause
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.step as Int, val.expectedStep)
                        }
                    }
                }
            }
        }.test(steps: 20)
    }
 
    func testDefer() {
        var innerVal = false
        var acc: Int = 0
        Module { name in
            activity (name.Inner, [], []) { val in
                exec { innerVal = true }
                `defer` { innerVal = false }
                halt
            }
            activity (name.Test, [name.cond], [name.val]) { val in
                when { val.cond } abort: {
                    cobegin {
                        with {
                            `defer` {
                                val.val = false
                                acc *= 2
                            }
                            exec { val.val = true }
                            `repeat` {
                                `defer` { acc += 1}
                                halt
                            }
                        }
                        with {
                            Pappe.run (name.Inner, [], [])
                        }
                    }
                }
                halt
            }
            activity (name.Main, []) { val in
                exec {
                    val.out = false
                }
                cobegin {
                    with {
                        exec {
                            val.cond = false
                            val.expect = true
                            val.accExpect = 0
                        }
                        pause
                        exec {
                            val.cond = true
                            val.expect = false
                            val.accExpect = 2
                        }
                        pause
                    }
                    with (.weak) {
                        Pappe.run (name.Test, [val.cond], [val.loc.out])
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.out as Bool, val.expect)
                            XCTAssertEqual(innerVal, val.expect)
                            XCTAssertEqual(acc, val.accExpect)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }
    
    func testDeferInMain() {
        var didCallDefer = false
        let m = Module { name in
            activity (name.Main, []) { val in
                `defer` { didCallDefer = true }
               pause
            }
        }
        let p = try! Processor(module: m)
        var done = false
        while !done {
            done = try! p.tick([], []) != .wait
        }

        XCTAssertTrue(didCallDefer)
    }
    
    func testSelectAndIf() {
        Module { name in
            activity (name.Test1, [name.val], [name.pos]) { val in
                `repeat` {
                    select {
                        match { val.val == 1 } then: {
                            exec { val.pos = 1 }
                        }
                        match { val.val == 2 } then: {
                            exec { val.pos = 2 }
                        }
                        otherwise {
                            exec { val.pos = 3 }
                        }
                    }
                    pause
                }
            }
            activity (name.Test2, [name.val], [name.pos]) { val in
                `repeat` {
                    `if` { val.val == 1 } then: {
                        exec { val.pos = 1 }
                    } else: {
                        `if` { val.val == 2 } then: {
                            exec { val.pos = 2 }
                        } else: {
                            exec { val.pos = 3 }
                        }
                    }
                    pause
                }
            }
            activity (name.Main, []) { val in
                exec {
                    val.pos1 = 0
                    val.pos2 = 0
                }
                cobegin {
                    with {
                        exec { val.test = 1 }
                        pause
                        exec { val.test = 2 }
                        pause
                        exec { val.test = 3 }
                        pause
                    }
                    with (.weak) {
                        Pappe.run (name.Test1, [val.test], [val.loc.pos1])
                    }
                    with (.weak) {
                        Pappe.run (name.Test2, [val.test], [val.loc.pos2])
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.pos1 as Int, val.test)
                            XCTAssertEqual(val.pos2 as Int, val.test)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }
    
    func testEvery() {
        Module { name in
            activity (name.Main, []) { val in
                exec { val.alternating = false }
                cobegin {
                    with (.weak) {
                        always {
                            val.res1 = false
                            val.res2 = false
                            let alternating: Bool = val.alternating
                            val.alternating = !alternating
                        }
                    }
                    with (.weak) {
                        always { val.expected1 = val.alternating as Bool }
                    }
                    with (.weak) {
                        exec { val.expected2 = false }
                        pause
                        always { val.expected2 = val.alternating as Bool }
                    }
                    with (.weak) {
                        nowAndEvery { val.alternating } do: {
                            val.res1 = true
                        }
                    }
                    with (.weak) {
                        every { val.alternating } do: {
                            val.res2 = true
                        }
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.expected1 as Bool, val.res1)
                            XCTAssertEqual(val.expected2 as Bool, val.res2)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }

    func testLoc() {
        let m = Module { name in
            activity (name.Main, [name.in], [name.out]) { val in
                always {
                    val.out = val.in as Int * 2
                }
            }
        }
        let p = m.makeProcessor()!
        for i in 0..<3 {
            let l = DirectLoc(val: 0)
            try! p.tick([i], [l])
            XCTAssertEqual(i * 2, l.val as! Int)
        }
    }
    
    func testMetaRun() {
        Module { name in
            activity (name.Target1, [], [name.tok]) { val in
                exec { val.tok = Int(1) }
                pause
            }
            activity (name.Target2, [], [name.tok]) { val in
                exec { val.tok = Int(2) }
                pause
            }
            activity (name.Meta, [name.target], [name.tok]) { val in
                Pappe.run (val.target, [], [val.loc.tok])
            }
            activity (name.Main, []) { val in
                exec { val.result = Int(0) }
                cobegin {
                    with {
                        exec {
                            val.target = "Target1"
                            val.expected = Int(1)
                        }
                        pause
                        exec {
                            val.target = "Target2"
                            val.expected = Int(2)
                        }
                        pause
                    }
                    with (.weak) {
                        `repeat` {
                            Pappe.run (name.Meta, [val.target], [val.loc.result])
                        }
                    }
                    with (.weak) {
                        always {
                            XCTAssertEqual(val.result as Int, val.expected as Int)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }

    func testPrev() {
        Module { name in
            activity (name.A, [name.x]) { val in
                exec {
                    XCTAssertEqual(val.x, 2)
                }
                pause
                exec {
                    val.x = 3
                    XCTAssertEqual(val.prev.x, 2)
                }
                halt
            }
            activity (name.Main, []) { val in
                exec {
                    XCTAssertEqual(val.prev[name.i, or: 0], 0)
                    val.i = 1
                }
                pause
                exec {
                    val.i = 2
                    XCTAssertEqual(val.prev.i, 1)
                }
                Pappe.run (name.A, [val.i])
            }
        }.test(steps: 10)
    }
    
    func testPrev2() {
        Module { name in
            activity (name.A, [name.x], [name.y]) { val in
                `repeat` {
                    exec {
                        val.prevX = val.x as Int
                        val.y += 1
                        val.prevY = val.y as Int
                    }
                    pause
                    exec {
                        XCTAssertEqual(val.prev.x, val.prevX as Int)
                        XCTAssertEqual(val.prev.y, val.prevY as Int)
                    }
                }
            }
            activity (name.Main, []) { val in
                exec {
                    val.x = 1
                    XCTAssertEqual(val.prev[name.x, or: 0], 0)
                }
                pause
                exec {
                    XCTAssertEqual(val.prev.x, 1)
                    val.x = 2
                    XCTAssertEqual(val.x, 2)
                    XCTAssertEqual(val.prev.x, 1)
                }
                
                exec { 
                    val.i = 0
                    val.j = 0
                }
                cobegin {
                    with {
                        always {
                            val.i += 1
                        }
                    }
                    with {
                        Pappe.run (name.A, [val.i], [val.loc.j])
                    }
                    with {
                        always {
                            XCTAssertEqual(val.i, val.j as Int)
                        }
                    }
                }
            }
        }.test(steps: 10)
    }
    
    func testPrev3() {
        Module { name in
            activity (name.Main, []) { val in
                exec {
                    val.i = 0
                    val.o = false
                }
                cobegin {
                    with {
                        pause
                        exec { val.i = 1 }
                    }
                    with {
                        when { val.i as Int != val.prev.i } abort: {
                            halt
                        }
                        exec { val.o = true }
                    }
                    with {
                        exec { XCTAssertFalse(val.o) }
                        pause
                        exec { XCTAssertTrue(val.o) }
                    }
                }
            }
        }.test(steps: 10)
    }

    static var allTests = [
        ("testAwait", testAwait),
        ("testReturn", testReturn),
        ("testCobegin", testCobegin),
        ("testRepeat", testRepeat),
        ("testAbort", testAbort),
        ("testAbortPrecedence", testAbortPrecedence),
        ("testReset", testReset),
        ("testDefer", testDefer),
        ("testDeferInMain", testDeferInMain),
        ("testSelectAndIf", testSelectAndIf),
        ("testEvery", testEvery),
        ("testLoc", testLoc),
        ("testMetaRun", testMetaRun),
        ("testPrev", testPrev),
        ("testPrev2", testPrev2),
        ("testPrev3", testPrev3),
    ]
}
