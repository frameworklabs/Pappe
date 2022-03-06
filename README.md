# Pappe

An embedded interpreted synchronous DSL for Swift.

## Background

This Swift Package allows you to experiment with synchronous programming in Swift. It follows the imperative synchronous programming language [Blech](https://blech-lang.org) and tries to recreate parts of it as an embedded interpreted DSL using the Swift `resultBuilders`.

The imperative synchronous approach allows preemption and concurrency in a structured and modular way.

## Usage

In this usage example three trails run concurrently for 10 ticks as determined by the first strong trail before printing "done". The second trail prints a message every third tick and the last trail every second tick.

```swift
let m = Module { name in
    activity (name.Wait, [name.ticks]) { val in
        exec { val.i = val.ticks as Int }
        while { val.i > 0 } repeat: {
            exec { val.i -= 1 }
            pause
        }
    }
    activity (name.Main, []) { val in
        cobegin {
            with {
                run (name.Wait, [10])
            }
            with (.weak) {
                `repeat` {
                    run (name.Wait, [2])
                    exec { print("on every third") }
                    pause
                }
            }
            with (.weak) {
                `repeat` {
                    run (name.Wait, [1])
                    exec { print("on every second") }
                    pause
                }
            }
        }
        exec { print("done") }
    }
}
```

For more extensive code examples, please have a look at:
* [Unit Tests](https://github.com/frameworklabs/Pappe/blob/master/Tests/PappeTests/PappeTests.swift)
* [BlinkerPappe](https://github.com/frameworklabs/BlinkerPappe) project. The Pappe code can be found in [this file](https://github.com/frameworklabs/BlinkerPappe/blob/master/BlinkerPappe/GameScene.swift).
* The [Synchrosphere](https://github.com/frameworklabs/Synchrosphere) project as well as the [SynchrosphereDemo](https://github.com/frameworklabs/SynchrosphereDemo) App which allows to control Sphero robots via imperative synchronous code. 
* [RangeExtender](https://github.com/frameworklabs/RangeExtender) which uses Pappe to simplify the setup and management of a Bluetooth LE connection.

The documentation of the SynchrosphereDemos can be seen as a [tutorial](https://github.com/frameworklabs/SynchrosphereDemo/blob/main/README.md#io-demos) for the Pappe language, as it explains its language constructs with concrete examples.

Finally, if you like the imperative synchronous programming concept, you might also be intrested in the [proto_activities](https://github.com/frameworklabs/proto_activities) project for embedded systems.

## Caveats

The Pappe DSL is more of a proof of concept. It has many shortcomings like:

* No causality checking.
* Interpreted instead of compiled.
* Untyped and unchecked variables.
* Poor Test coverage.
