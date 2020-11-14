# Pappe

An embedded interpreted synchronous DSL for Swift.

## Background

This Swift Package allows you to experiment with synchronous programming in Swift. It follows the imperative synchronous programming language [Blech](https://blech-lang.org) and tries to recreate parts of it as an embedded interpreted DSL using the Swift `functionBuilders`.

The imperative synchronous approach gives you control over the (logical) timing aspects of your program turning them from non-functional to functional qualities.

## Usage

For now, please have a look at Tests or at the [BlinkerPappe Project](https://github.com/frameworklabs/BlinkerPappe). The Pappe code can be found in [this file](https://github.com/frameworklabs/BlinkerPappe/blob/master/BlinkerPappe/GameScene.swift).

## Caveats

The Pappe DSL is more of a proof of concept. It has many shortcommings like:

* No causality checking.
* Interpreted instead of compiled.
* Untyped and unchecked variables.
* Poor Test coverage.
