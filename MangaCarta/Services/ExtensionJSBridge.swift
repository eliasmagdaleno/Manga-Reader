//
//  ExtensionJSBridge.swift
//  MangaCarta
//
//  The value boundary between a JavaScriptCore context and the host.
//
//  The Host API design's "Envelope and value rules" section names eight kinds that
//  may not cross: `undefined`, functions, symbols, cyclic objects, non-finite
//  numbers, dates, typed arrays, and host objects. Several of those are *erased* by
//  `JSValue.toObject()` — an `undefined`-valued property disappears, a function and a
//  typed array both arrive as objects, a `Date` arrives as an `NSDate` that a
//  dictionary walk can mistake for data. So every rule here is applied to the live
//  `JSValue`, before any Foundation conversion. A kind check made after conversion is
//  not a check.
//
//  Structure is inspected through builtins snapshotted at construction, before any
//  Extension code has run in the context. An engine that reassigns
//  `Object.getOwnPropertyNames` therefore changes nothing about what crosses.
//
//  What comes out is ordinary JSON-shaped Foundation (`NSNull`, `NSNumber`, `String`,
//  `[Any]`, `[String: Any]`) — exactly what `ExtensionDomainValidator` consumes. This
//  file decides *whether a value is JSON*; that validator decides *whether the JSON is
//  a Listing*. Neither repeats the other.
//

import Foundation
import JavaScriptCore

/// Pristine references to the builtins the bridge needs, captured before Extension
/// code can reassign them.
private struct ExtensionJSIntrinsics {
    let objectPrototype: JSValue
    let arrayPrototype: JSValue
    let getPrototypeOf: JSValue
    let getOwnPropertyNames: JSValue
    let getOwnPropertySymbols: JSValue
    let getOwnPropertyDescriptor: JSValue
    let freeze: JSValue

    init?(context: JSContext) {
        guard let object = context.objectForKeyedSubscript("Object"),
              let array = context.objectForKeyedSubscript("Array"),
              let objectPrototype = object.objectForKeyedSubscript("prototype"),
              let arrayPrototype = array.objectForKeyedSubscript("prototype"),
              let getPrototypeOf = object.objectForKeyedSubscript("getPrototypeOf"),
              let names = object.objectForKeyedSubscript("getOwnPropertyNames"),
              let symbols = object.objectForKeyedSubscript("getOwnPropertySymbols"),
              let descriptor = object.objectForKeyedSubscript("getOwnPropertyDescriptor"),
              let freeze = object.objectForKeyedSubscript("freeze"),
              !objectPrototype.isUndefined, !arrayPrototype.isUndefined,
              !getPrototypeOf.isUndefined, !names.isUndefined, !symbols.isUndefined,
              !descriptor.isUndefined, !freeze.isUndefined else {
            return nil
        }
        self.objectPrototype = objectPrototype
        self.arrayPrototype = arrayPrototype
        self.getPrototypeOf = getPrototypeOf
        self.getOwnPropertyNames = names
        self.getOwnPropertySymbols = symbols
        self.getOwnPropertyDescriptor = descriptor
        self.freeze = freeze
    }
}

/// Converts values across the JavaScriptCore boundary in both directions.
///
/// One bridge belongs to one `JSContext` and must be used only where that context is
/// used — see `ExtensionRuntime` for the isolation rule.
final class ExtensionJSBridge {

    /// Bounds recursion so a deeply nested result cannot overflow the stack. This is a
    /// host tuning constant, not contract: the design's first open evidence gate covers
    /// exact limits, and nothing about the wire contract depends on this number.
    static let maximumDepth = 128

    private static let maximumSafeJSONInteger = 9_007_199_254_740_991.0

    private unowned let context: JSContext
    private let intrinsics: ExtensionJSIntrinsics

    /// Fails only if the context has no usable `Object`/`Array` — which cannot happen
    /// in a freshly created context, and is exactly the state in which nothing should
    /// be trusted to cross.
    init?(context: JSContext) {
        guard let intrinsics = ExtensionJSIntrinsics(context: context) else { return nil }
        self.context = context
        self.intrinsics = intrinsics
    }

    // MARK: - JavaScript to host

    /// Converts a JavaScript value to JSON-shaped Foundation, rejecting everything the
    /// design's value rules forbid.
    func jsonValue(from value: JSValue, path: String = "value") throws -> Any {
        var ancestors: [OpaquePointer] = []
        return try convert(value, path: path, depth: 0, ancestors: &ancestors)
    }

    private func convert(_ value: JSValue,
                         path: String,
                         depth: Int,
                         ancestors: inout [OpaquePointer]) throws -> Any {
        guard depth <= Self.maximumDepth else {
            throw reject(path, "value is nested deeper than the host accepts")
        }

        if let scalar = try scalar(value, path: path) { return scalar }
        try requireConvertibleObject(value, path: path)

        let identity = value.jsValueRef!
        guard !ancestors.contains(identity) else {
            throw reject(path, "cyclic values are not JSON values")
        }
        ancestors.append(identity)
        defer { ancestors.removeLast() }

        try rejectSymbolKeys(value, path: path)
        if value.isArray {
            return try array(value, path: path, depth: depth, ancestors: &ancestors)
        }
        return try object(value, path: path, depth: depth, ancestors: &ancestors)
    }

    /// The non-container kinds, plus every forbidden kind that a container check would
    /// otherwise mistake for a container. `nil` means "this is a container".
    ///
    /// Order matters: `isObject` is also true for functions, arrays, dates, typed
    /// arrays and host objects, so every narrower kind is decided first.
    private func scalar(_ value: JSValue, path: String) throws -> Any? {
        if value.isUndefined { throw reject(path, "undefined is not a JSON value") }
        if value.isNull { return NSNull() }
        if value.isBoolean { return NSNumber(value: value.toBool()) }
        if value.isNumber { return try number(value, path: path) }
        if value.isString { return value.toString() ?? "" }
        if value.isSymbol { throw reject(path, "symbols are not JSON values") }
        if value.isDate { throw reject(path, "dates are not JSON values") }
        return nil
    }

    private func requireConvertibleObject(_ value: JSValue, path: String) throws {
        guard value.isObject else { throw reject(path, "value is not JSON-compatible") }
        if isFunction(value) { throw reject(path, "functions are not JSON values") }
        if isTypedArray(value) { throw reject(path, "typed arrays are not JSON values") }
    }

    private func number(_ value: JSValue, path: String) throws -> Any {
        let double = value.toDouble()
        guard double.isFinite else {
            throw reject(path, "non-finite numbers are not JSON values")
        }
        guard double.rounded(.towardZero) != double else {
            guard abs(double) <= Self.maximumSafeJSONInteger,
                  let integer = Int(exactly: double) else {
                throw reject(path, "integer is outside the safe JSON range")
            }
            return NSNumber(value: integer)
        }
        return NSNumber(value: double)
    }

    private func array(_ value: JSValue,
                       path: String,
                       depth: Int,
                       ancestors: inout [OpaquePointer]) throws -> [Any] {
        try requirePrototype(value, is: intrinsics.arrayPrototype, path: path)

        let lengthValue = value.forProperty("length")
        let length = Int(lengthValue?.toUInt32() ?? 0)
        var items: [Any] = []
        items.reserveCapacity(length)
        for index in 0..<length {
            guard let element = value.atIndex(index) else {
                throw reject("\(path)[\(index)]", "undefined is not a JSON value")
            }
            items.append(try convert(element,
                                     path: "\(path)[\(index)]",
                                     depth: depth + 1,
                                     ancestors: &ancestors))
        }

        // An array's own names are its indexes plus `length`. Anything else is a
        // property `JSON.stringify` would have silently dropped.
        let names = try ownPropertyNames(of: value, path: path)
        guard names.count == length + 1 else {
            throw reject(path, "arrays may not carry own properties beyond their elements")
        }
        return items
    }

    private func object(_ value: JSValue,
                        path: String,
                        depth: Int,
                        ancestors: inout [OpaquePointer]) throws -> [String: Any] {
        try requirePlainObject(value, path: path)

        var output: [String: Any] = [:]
        for name in try ownPropertyNames(of: value, path: path) {
            let childPath = "\(path).\(name)"
            let descriptor = try call(intrinsics.getOwnPropertyDescriptor,
                                      arguments: [value, name],
                                      path: childPath)
            guard descriptor.isObject else {
                throw reject(childPath, "property is not readable as data")
            }
            // Reading through a getter would run Extension code in the middle of
            // validation. The descriptor's own `value` slot never does.
            let getter = descriptor.forProperty("get")
            let setter = descriptor.forProperty("set")
            if getter?.isUndefined == false || setter?.isUndefined == false {
                throw reject(childPath, "accessor properties are not JSON values")
            }
            guard let slot = descriptor.forProperty("value") else {
                throw reject(childPath, "property is not readable as data")
            }
            output[name] = try convert(slot,
                                       path: childPath,
                                       depth: depth + 1,
                                       ancestors: &ancestors)
        }
        return output
    }

    // MARK: - Host to JavaScript

    /// Injects JSON-shaped Foundation into the context and deep-freezes it.
    ///
    /// The design's "Configuration-first Sources" section says configuration is
    /// deep-frozen before invocation; the same treatment is applied to every request
    /// value, because an engine that mutates its own request argument would make the
    /// host's record of what it asked for a lie.
    func frozenValue(from json: Any) throws -> JSValue {
        guard let value = JSValue(object: json, in: context) else {
            throw reject("request", "host value is not representable in JavaScript")
        }
        try deepFreeze(value, path: "request", depth: 0)
        return value
    }

    private func deepFreeze(_ value: JSValue, path: String, depth: Int) throws {
        guard depth <= Self.maximumDepth else {
            throw reject(path, "value is nested deeper than the host accepts")
        }
        guard value.isObject, !isFunction(value) else { return }

        if value.isArray {
            let length = Int(value.forProperty("length")?.toUInt32() ?? 0)
            for index in 0..<length {
                if let element = value.atIndex(index) {
                    try deepFreeze(element, path: "\(path)[\(index)]", depth: depth + 1)
                }
            }
        } else {
            for name in try ownPropertyNames(of: value, path: path) {
                if let child = value.forProperty(name) {
                    try deepFreeze(child, path: "\(path).\(name)", depth: depth + 1)
                }
            }
        }
        _ = try call(intrinsics.freeze, arguments: [value], path: path)
    }

    // MARK: - Kind and structure helpers

    private func isFunction(_ value: JSValue) -> Bool {
        guard let ref = value.jsValueRef,
              let object = JSValueToObject(context.jsGlobalContextRef, ref, nil) else {
            return false
        }
        return JSObjectIsFunction(context.jsGlobalContextRef, object)
    }

    private func isTypedArray(_ value: JSValue) -> Bool {
        guard let ref = value.jsValueRef else { return false }
        let kind = JSValueGetTypedArrayType(context.jsGlobalContextRef, ref, nil)
        return kind != kJSTypedArrayTypeNone
    }

    private func requirePlainObject(_ value: JSValue, path: String) throws {
        let prototype = try call(intrinsics.getPrototypeOf, arguments: [value], path: path)
        guard prototype.isNull || prototype.isEqual(to: intrinsics.objectPrototype) else {
            throw reject(path, "only plain objects are JSON values")
        }
    }

    private func requirePrototype(_ value: JSValue,
                                  is expected: JSValue,
                                  path: String) throws {
        let prototype = try call(intrinsics.getPrototypeOf, arguments: [value], path: path)
        guard prototype.isEqual(to: expected) else {
            throw reject(path, "only plain arrays are JSON values")
        }
    }

    private func rejectSymbolKeys(_ value: JSValue, path: String) throws {
        let symbols = try call(intrinsics.getOwnPropertySymbols,
                               arguments: [value],
                               path: path)
        guard Int(symbols.forProperty("length")?.toUInt32() ?? 0) == 0 else {
            throw reject(path, "symbol-keyed properties are not JSON values")
        }
    }

    private func ownPropertyNames(of value: JSValue, path: String) throws -> [String] {
        let names = try call(intrinsics.getOwnPropertyNames, arguments: [value], path: path)
        let count = Int(names.forProperty("length")?.toUInt32() ?? 0)
        var output: [String] = []
        output.reserveCapacity(count)
        for index in 0..<count {
            guard let name = names.atIndex(index)?.toString() else {
                throw reject(path, "property name is not readable")
            }
            output.append(name)
        }
        return output
    }

    /// Calls a snapshotted builtin and turns any JavaScript exception into a rejection
    /// rather than leaving it on the context, where it would surface as an unrelated
    /// failure much later.
    private func call(_ function: JSValue,
                      arguments: [Any],
                      path: String) throws -> JSValue {
        let previousException = context.exception
        context.exception = nil
        let result = function.call(withArguments: arguments)
        let raised = context.exception
        context.exception = previousException
        if raised != nil {
            throw reject(path, "inspecting the value raised a JavaScript exception")
        }
        guard let result else {
            throw reject(path, "inspecting the value produced no result")
        }
        return result
    }

    private func reject(_ path: String, _ reason: String) -> ExtensionSchemaError {
        ExtensionSchemaError(fieldPath: path, reason: reason)
    }
}
