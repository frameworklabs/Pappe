# Pappe

An embedded interpreted synchronous DSL for Swift.

## Background

This Swift Package allows you to experiment with synchronous programming in Swift. It follows the imperative synchronous programming language [Blech](https://blech-lang.org) and tries to recreate parts of it as an embedded interpreted DSL using the Swift `functionBuilders`.

The imperative synchronous approach gives you control over the (logical) timing aspects of your program turning them from non-functional to functional qualities.

## Usage

In this usage example three trails run concurrently for 10 ticks as determined by the first strong trail before printing "done". The second trail prints a message every third tick and the last trail every second tick.

```swift
let m = Module { name in
    activity (name.Wait, [name.ticks]) { val in
        exec { val.i = val.ticks as Int }
        while { val.i > 0 } repeat: {
            exec { val.i -= 1 }
            await { true }
        }
    }
    activity (name.Main, []) { val in
        cobegin {
            strong {
                run (name.Wait, [10])
            }
            weak {
                `repeat` {
                    run (name.Wait, [2])
                    exec { print("on every third") }
                    await { true }
                }
            }
            weak {
                `repeat` {
                    run (name.Wait, [1])
                    exec { print("on every second") }
                    await { true }
                }
            }
        }
        exec { print("done") }
    }
}
```

For more extensive code examples, please have a look at the [Unit Tests](https://github.com/frameworklabs/Pappe/blob/master/Tests/PappeTests/PappeTests.swift) or at the [BlinkerPappe Project](https://github.com/frameworklabs/BlinkerPappe). The Pappe code can be found in [this file](https://github.com/frameworklabs/BlinkerPappe/blob/master/BlinkerPappe/GameScene.swift).

## Caveats

The Pappe DSL is more of a proof of concept. It has many shortcommings like:

* No causality checking.
* Interpreted instead of compiled.
* Untyped and unchecked variables.
* Poor Test coverage.
