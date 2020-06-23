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
            whileRepeat (val.i > 0) {
                exec { val.i -= 1 }
                await { true }
            }
        }
        noAct
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
                        doRun (name.Test, [val.in1, val.in2], [val.loc.out])
                        nop
                    }
                    weak {
                        loop {
                            exec { XCTAssertEqual(val.out as Bool, val.expect) }
                            await { true }
                        }
                        nop
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
                whenAbort (false) {
                    loop {
                        await { true }
                        doRun (name.Inner, []) { res in val.tmp = res }
                        exit { val.tmp }
                        await { false }
                    }
                    nop
                }
                nop
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
                        doRun (name.Test, []) { res in val.out = res }
                        nop
                    }
                    weak {
                        loop {
                            exec { XCTAssertEqual(val.out as Int, val.expect) }
                            await { true }
                        }
                        nop
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
                        doRun (name.Delay, [1])
                        nop
                    }
                    strong {
                        doRun (name.Delay, [3])
                        nop
                    }
                    strong {
                        doRun (name.Delay, [2])
                        nop
                    }
                    weak {
                        doRun (name.Delay, [2])
                        nop
                    }
                    weak {
                        doRun (name.Delay, [4])
                        nop
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
                        doRun (name.Test, [], [val.loc.out])
                        nop
                    }
                    weak {
                        loop {
                            exec { XCTAssertEqual(val.out as Bool, val.expect) }
                            await { true }
                        }
                        nop
                    }
                }
            }
        }.test(steps: 10)
    }

    func testRepeat() {
        Module { name in
            activity (name.TestRepeatUntil, [], [name.done]) { val in
                exec { val.i = 3 }
                repeatUntil ({
                    exec { val.i -= 1 }
                    await { true }
                }, val.i == 0)
                exec { val.done = true }
            }
            activity (name.TestWhileRepeat, [], [name.done]) { val in
                exec { val.i = 3 }
                whileRepeat (val.i > 0) {
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
                        doRun (name.TestRepeatUntil, [], [val.loc.outRepeatUntil])
                        nop
                    }
                    weak {
                        doRun (name.TestWhileRepeat, [], [val.loc.outWhileRepeat])
                        nop
                    }
                    weak {
                        loop {
                            exec {
                                XCTAssertEqual(val.outRepeatUntil as Bool, val.expect)
                                XCTAssertEqual(val.outWhileRepeat as Bool, val.expect)
                            }
                            await { true }
                        }
                        nop
                    }
                }
            }
        }.test(steps: 10)
    }
    
    func testAbort() {
        Module(imports: [common]) { name in
            activity (name.Test, [], [name.pos]) { val in
                whenAbort (true) {
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
                        doRun (name.Test, [], [val.loc.out])
                        nop
                    }
                    weak {
                        loop {
                            exec { XCTAssertEqual(val.out as Int, val.expect) }
                            await { true }
                        }
                        nop
                    }
                }
            }
        }.test(steps: 10)
    }
    static var allTests = [
        ("testAwait", testAwait),
        ("testExit", testExit),
        ("testCobegin", testCobegin),
        ("testRepeat", testRepeat),
        ("testAbort", testAbort),
    ]
}
