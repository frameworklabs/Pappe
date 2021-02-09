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
                await { true }
            }
        }
    }
    
    func testAwait() {
        Module { name in
            activity (name.Test, [name.in1, name.in2], [name.out]) { val in
                exec { val.out = false }
                await { val.in1 && val.in2 }
                exec { val.out = true }
            }
            activity (name.Main, []) { val in
                exec { val.out =  false }
                cobegin {
                    strong {
                        exec {
                            val.in1 = false
                            val.in2 = false
                            val.expect = false
                        }
                        await { true }
                        exec {
                            val.in1 = true
                            val.in2 = false
                            val.expect = false
                        }
                        await { true }
                        exec {
                            val.in1 = false
                            val.in2 = true
                            val.expect = false
                        }
                        await { true }
                        exec {
                            val.in1 = true
                            val.in2 = true
                            val.expect = true
                        }
                    }
                    weak {
                        Pappe.run (name.Test, [val.in1, val.in2], [val.loc.out])
                    }
                    weak {
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
                await { false }
            }
            activity (name.Test, []) { val in
                when { false } abort: {
                    `repeat` {
                        await { true }
                        Pappe.run  (name.Inner, []) { res in val.tmp = res }
                        `return` { val.tmp }
                        await { false }
                    }
                }
            }
            activity (name.Main, []) { val in
                exec { val.out = 0 }
                cobegin {
                    strong {
                        exec { val.expect = 0 }
                        await { true }
                        exec { val.expect = 42 }
                        await { true }
                    }
                    weak {
                        Pappe.run  (name.Test, []) { res in val.out = res }
                    }
                    weak {
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
                    strong {
                        Pappe.run (name.Delay, [1])
                    }
                    strong {
                        Pappe.run (name.Delay, [3])
                    }
                    strong {
                        Pappe.run (name.Delay, [2])
                    }
                    weak {
                        Pappe.run (name.Delay, [2])
                    }
                    weak {
                        Pappe.run (name.Delay, [4])
                    }
                }
                exec { val.done = true }
            }
            activity (name.Main, []) { val in
                exec { val.out = false }
                cobegin {
                    strong {
                        exec { val.expect = false }
                        await { true }
                        exec { val.expect = false }
                        await { true }
                        exec { val.expect = false }
                        await { true }
                        exec { val.expect = true }
                    }
                    weak {
                        Pappe.run (name.Test, [], [val.loc.out])
                    }
                    weak {
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
                    await { true }
                } until: { val.i == 0 }
                exec { val.done = true }
            }
            activity (name.TestWhileRepeat, [], [name.done]) { val in
                exec { val.i = 3 }
                `while` { val.i > 0 } repeat: {
                    exec { val.i -= 1 }
                    await { true }
                }
                exec { val.done = true }
            }
            activity (name.Main, []) { val in
                exec {
                    val.outRepeatUntil = false
                    val.outWhileRepeat = false
                }
                cobegin {
                    strong {
                        exec { val.expect = false }
                        await { true }
                        exec { val.expect = false }
                        await { true }
                        exec { val.expect = false }
                        await { true }
                        exec { val.expect = true }
                    }
                    weak {
                        Pappe.run (name.TestRepeatUntil, [], [val.loc.outRepeatUntil])
                    }
                    weak {
                        Pappe.run (name.TestWhileRepeat, [], [val.loc.outWhileRepeat])
                    }
                    weak {
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
                    await { true }
                    exec { val.pos = 2 }
                    await { true }
                }
                exec { val.pos = 3 }
            }
            activity (name.Main, []) { val in
                exec { val.out = 0 }
                cobegin {
                    strong {
                        exec { val.expect = 1 }
                        await { true }
                        exec { val.expect = 3 }
                    }
                    weak {
                        Pappe.run (name.Test, [], [val.loc.out])
                    }
                    weak {
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
                        await { false }
                    }
                    exec { val.seenInner = true }
                    await { false }
                }
                exec { val.seenOuter = true }
                await { false }
            }
            activity (name.Main, []) { val in
                exec {
                    val.reachedInner = false
                    val.seenOuter = false
                    val.seenInner = false
                }
                cobegin {
                    strong {
                        exec {
                            val.outer = false
                            val.inner = false
                            val.expectedOuter = false
                            val.expectedInner = false
                        }
                        await { true }
                        exec {
                            val.outer = true
                            val.inner = true
                            val.expectedOuter = true
                            val.expectedInner = false
                        }
                        await { true }
                    }
                    weak {
                        Pappe.run (name.Test, [val.outer, val.inner], [val.loc.reachedInner, val.loc.seenOuter, val.loc.seenInner])
                    }
                    weak {
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
                    strong {
                        exec {
                            val.cond = false
                            val.step = 0
                            val.expectedStep = 1
                        }
                        await { true }
                        exec { val.expectedStep = 2 }
                        await { true }
                        exec { val.expectedStep = 3 }
                        await { true }
                        
                        exec { val.expectedStep = 1 }
                        await { true }
                        exec {
                            val.cond = true
                            val.expectedStep = 2
                        }
                        await { true }
                        exec {
                            val.cond = false
                            val.expectedStep = 12
                        }
                        await { true }
                        exec { val.expectedStep = 112 }
                        await { true }
                        
                        exec { val.expectedStep = 1 }
                        await { true }
                        exec {
                            val.innerCond = true
                            val.expectedStep = 2
                        }
                        await { true }
                        exec {
                            val.innerCond = false
                            val.expectedStep = 12
                        }
                        await { true }
                        exec { val.expectedStep = 112 }
                        await { true }
                        exec { val.expectedStep = 1112 }
                        await { true }
                    }
                    weak {
                        when { val.cond } reset: {
                            exec { val.step = 1 }
                            await { true }
                            exec { val.step = 2}
                            await { true }
                        }
                        exec { val.step = 3 }
                        await { true }
                        
                        exec { val.step = 0 }
                        when { val.cond } reset: {
                            exec { val.step = val.step + 1 }
                            await { true }
                            exec { val.step = val.step + 10 }
                            await { true }
                        }
                        exec { val.step = val.step + 100 }
                        await { true }
                        
                        exec { val.step = 0 }
                        when { val.cond } reset: {
                            when { val.innerCond } reset: {
                                exec { val.step = val.step + 1 }
                                await { true }
                                exec { val.step = val.step + 10 }
                                await { true }
                            }
                            exec { val.step = val.step + 100 }
                            await { true }
                        }
                        exec { val.step = val.step + 1000 }
                        await { true }
                    }
                    weak {
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
        Module { name in
            activity (name.Inner, [], []) { val in
                exec { innerVal = true }
                `defer` { innerVal = false }
                await { false }
            }
            activity (name.Test, [name.cond], [name.val]) { val in
                when { val.cond } abort: {
                    cobegin {
                        strong {
                            `defer` { val.val = false }
                            exec { val.val = true }
                            await { false }
                        }
                        strong {
                            Pappe.run (name.Inner, [], [])
                        }
                    }
                }
                await { false }
            }
            activity (name.Main, []) { val in
                exec {
                    val.out = false
                }
                cobegin {
                    strong {
                        exec {
                            val.cond = false
                            val.expect = true
                        }
                        await { true }
                        exec {
                            val.cond = true
                            val.expect = false
                        }
                        await { true }
                    }
                    weak {
                        Pappe.run (name.Test, [val.cond], [val.loc.out])
                    }
                    weak {
                        always {
                            XCTAssertEqual(val.out as Bool, val.expect)
                            XCTAssertEqual(innerVal as Bool, val.expect)
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
                await { true }
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
                    await { true }
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
                    await { true }
                }
            }
            activity (name.Main, []) { val in
                exec {
                    val.pos1 = 0
                    val.pos2 = 0
                }
                cobegin {
                    strong {
                        exec { val.test = 1 }
                        await { true }
                        exec { val.test = 2 }
                        await { true }
                        exec { val.test = 3 }
                        await { true }
                    }
                    weak {
                        Pappe.run (name.Test1, [val.test], [val.loc.pos1])
                    }
                    weak {
                        Pappe.run (name.Test2, [val.test], [val.loc.pos2])
                    }
                    weak {
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
                    weak {
                        always {
                            val.res1 = false
                            val.res2 = false
                            let alternating: Bool = val.alternating
                            val.alternating = !alternating
                        }
                    }
                    weak {
                        always { val.expected1 = val.alternating as Bool }
                    }
                    weak {
                        exec { val.expected2 = false }
                        await { true }
                        always { val.expected2 = val.alternating as Bool }
                    }
                    weak {
                        nowAndEvery { val.alternating } do: {
                            val.res1 = true
                        }
                    }
                    weak {
                        every { val.alternating } do: {
                            val.res2 = true
                        }
                    }
                    weak {
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
    ]
}
