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
                        `repeat` {
                            exec { XCTAssertEqual(val.out as Bool, val.expect) }
                            await { true }
                        }
                    }
                }
            }
        }.test(steps: 10)
    }

    func testExit() {
        Module { name in
            activity (name.Inner, []) { val in
                exit { 42 }
                await { false }
            }
            activity (name.Test, []) { val in
                when { false } abort: {
                    `repeat` {
                        await { true }
                        Pappe.run  (name.Inner, []) { res in val.tmp = res }
                        exit { val.tmp }
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
                        `repeat` {
                            exec { XCTAssertEqual(val.out as Int, val.expect) }
                            await { true }
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
                        `repeat` {
                            exec { XCTAssertEqual(val.out as Bool, val.expect) }
                            await { true }
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
                        `repeat` {
                            exec {
                                XCTAssertEqual(val.outRepeatUntil as Bool, val.expect)
                                XCTAssertEqual(val.outWhileRepeat as Bool, val.expect)
                            }
                            await { true }
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
                        `repeat` {
                            exec { XCTAssertEqual(val.out as Int, val.expect) }
                            await { true }
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
                        `repeat` {
                            exec {
                                XCTAssertEqual(val.reachedInner as Bool, true)
                                XCTAssertEqual(val.seenOuter as Bool, val.expectedOuter)
                                XCTAssertEqual(val.seenInner as Bool, val.expectedInner)
                            }
                            await { true }
                        }
                    }
                }
            }
        }.test(steps: 10)
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
                        `repeat` {
                            exec { XCTAssertEqual(val.out as Bool, val.expect) }
                            exec { XCTAssertEqual(innerVal as Bool, val.expect) }
                            await { true }
                        }
                    }
                }
            }
        }.test(steps: 10)
    }

    func testLoc() {
        let m = Module { name in
            activity (name.Main, [name.in], [name.out]) { val in
                `repeat` {
                    exec { val.out = val.in as Int * 2 }
                    await { true }
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
        ("testExit", testExit),
        ("testCobegin", testCobegin),
        ("testRepeat", testRepeat),
        ("testAbort", testAbort),
        ("testAbortPrecedence", testAbortPrecedence),
        ("testLoc", testLoc),
    ]
}
