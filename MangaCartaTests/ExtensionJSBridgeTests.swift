//
//  ExtensionJSBridgeTests.swift
//  MangaCartaTests
//
//  The pre-conversion boundary. The Host API design's "Envelope and value rules"
//  section lists what may not cross: `undefined`, functions, symbols, cyclic
//  objects, non-finite numbers, dates, typed arrays, and host objects. Every one
//  of those has a Foundation analogue that is indistinguishable from valid data
//  once `JSValue.toObject()` has run, so each case here is asserted against a
//  live `JSValue` rather than against a converted `NSDictionary`.
//

import Foundation
import JavaScriptCore
import XCTest
@testable import MangaCarta

final class ExtensionJSBridgeTests: XCTestCase {

    private var context: JSContext!
    private var bridge: ExtensionJSBridge!

    override func setUp() {
        super.setUp()
        context = JSContext()
        bridge = ExtensionJSBridge(context: context)
    }

    override func tearDown() {
        bridge = nil
        context = nil
        super.tearDown()
    }

    /// Evaluates an expression *after* the intrinsics snapshot exists, which is the
    /// order the runtime uses: host first, Extension code second.
    private func evaluate(_ script: String) -> JSValue {
        let value = context.evaluateScript("(function () { \(script) })()")!
        XCTAssertNil(context.exception, "script threw: \(String(describing: context.exception))")
        return value
    }

    private func expectRejection(_ script: String,
                                 containing fragment: String,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        do {
            let converted = try bridge.jsonValue(from: evaluate(script))
            XCTFail("expected rejection, converted to \(converted)", file: file, line: line)
        } catch let error as ExtensionSchemaError {
            XCTAssertEqual(error.code, .invalidResponse, file: file, line: line)
            XCTAssertTrue(error.reason.contains(fragment),
                          "reason was \(error.reason)", file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    // MARK: - Values that must cross

    func testConvertsJSONScalarsAndContainers() throws {
        let value = try bridge.jsonValue(from: evaluate("""
            return { s: "text", n: 1.5, i: 42, t: true, f: false, z: null,
                     a: [1, "two", [3]], o: { nested: { deep: true } } };
        """))

        let object = try XCTUnwrap(value as? [String: Any])
        XCTAssertEqual(object["s"] as? String, "text")
        XCTAssertEqual(object["n"] as? Double, 1.5)
        XCTAssertEqual(object["i"] as? Int, 42)
        XCTAssertEqual(object["t"] as? Bool, true)
        XCTAssertEqual(object["f"] as? Bool, false)
        XCTAssertTrue(object["z"] is NSNull)
        XCTAssertEqual((object["a"] as? [Any])?.count, 3)
        XCTAssertNotNil(object["o"] as? [String: Any])
    }

    /// Booleans must survive as `CFBoolean`, because the domain validator S2 built
    /// separates `true` from `1` by exactly that test.
    func testBooleansSurviveAsCoreFoundationBooleans() throws {
        let value = try bridge.jsonValue(from: evaluate("return { flag: true, one: 1 };"))
        let object = try XCTUnwrap(value as? [String: Any])
        let flag = try XCTUnwrap(object["flag"] as? NSNumber)
        let one = try XCTUnwrap(object["one"] as? NSNumber)
        XCTAssertEqual(CFGetTypeID(flag), CFBooleanGetTypeID())
        XCTAssertNotEqual(CFGetTypeID(one), CFBooleanGetTypeID())
    }

    func testAcceptsNullPrototypeObject() throws {
        let value = try bridge.jsonValue(from: evaluate("""
            var o = Object.create(null); o.id = "x"; return o;
        """))
        XCTAssertEqual((value as? [String: Any])?["id"] as? String, "x")
    }

    // MARK: - The eight invalid kinds

    func testRejectsUndefinedPropertyBeforeConversion() {
        expectRejection("return { id: \"a\", extra: undefined };", containing: "undefined")
    }

    func testRejectsTopLevelUndefined() {
        expectRejection("return undefined;", containing: "undefined")
    }

    func testRejectsFunctionValuedProperty() {
        expectRejection("return { id: \"a\", go: function () { return 1; } };",
                        containing: "function")
    }

    func testRejectsArrowFunctionValuedProperty() {
        expectRejection("return { go: () => 1 };", containing: "function")
    }

    func testRejectsSymbolValue() {
        expectRejection("return { s: Symbol(\"x\") };", containing: "symbol")
    }

    func testRejectsSymbolKeyedProperty() {
        expectRejection("""
            var o = { id: "a" }; o[Symbol("hidden")] = 1; return o;
        """, containing: "symbol")
    }

    func testRejectsCyclicObject() {
        expectRejection("var o = { id: \"a\" }; o.self = o; return o;", containing: "cyclic")
    }

    func testRejectsCyclicArray() {
        expectRejection("var a = [1]; a.push(a); return a;", containing: "cyclic")
    }

    func testRejectsNonFiniteNumbers() {
        expectRejection("return { n: NaN };", containing: "non-finite")
        expectRejection("return { n: Infinity };", containing: "non-finite")
        expectRejection("return { n: -Infinity };", containing: "non-finite")
    }

    func testRejectsUnsafeInteger() {
        expectRejection("return { n: 9007199254740993 };", containing: "safe JSON")
    }

    func testRejectsDate() {
        expectRejection("return { at: new Date(0) };", containing: "date")
    }

    func testRejectsTypedArrayAndArrayBuffer() {
        expectRejection("return { bytes: new Uint8Array([1, 2, 3]) };", containing: "typed array")
        expectRejection("return { bytes: new ArrayBuffer(4) };", containing: "typed array")
    }

    /// A Swift value exported into the context is a host object. After conversion it
    /// is an `NSDictionary` like any other; before conversion its prototype is not
    /// `Object.prototype`.
    func testRejectsHostObject() {
        context.setObject(HostObjectStub(), forKeyedSubscript: "hostThing" as NSString)
        expectRejection("return { thing: hostThing };", containing: "plain")
    }

    func testRejectsClassInstanceErrorRegExpMapAndPromise() {
        expectRejection("class C { constructor() { this.x = 1; } } return { v: new C() };",
                        containing: "plain")
        expectRejection("return { v: new Error(\"boom\") };", containing: "plain")
        expectRejection("return { v: /x/ };", containing: "plain")
        expectRejection("return { v: new Map() };", containing: "plain")
        expectRejection("return { v: Promise.resolve(1) };", containing: "plain")
    }

    func testRejectsArraySubclassAndArrayHole() {
        expectRejection("class A extends Array {} return { v: A.from([1]) };",
                        containing: "plain")
        expectRejection("return { v: [1, , 3] };", containing: "undefined")
    }

    /// Reading a property must not run Extension code: a getter is refused rather
    /// than invoked, so conversion cannot re-enter the engine mid-validation.
    func testRejectsAccessorProperty() {
        expectRejection("""
            var o = {}; Object.defineProperty(o, "id", { get: function () { return "a"; },
                                                        enumerable: true });
            return o;
        """, containing: "accessor")
    }

    func testRejectsNonEnumerableFunctionProperty() {
        expectRejection("""
            var o = { id: "a" };
            Object.defineProperty(o, "hidden", { value: function () {}, enumerable: false });
            return o;
        """, containing: "function")
    }

    // MARK: - The intrinsics snapshot

    /// Every structural question is asked through builtins captured before Extension
    /// code ran, so redefining them cannot smuggle a value across.
    func testOverwrittenBuiltinsCannotSmuggleAFunctionAcross() {
        context.evaluateScript("""
            Object.getOwnPropertyNames = function () { return []; };
            Object.getOwnPropertySymbols = function () { return []; };
            Object.getPrototypeOf = function () { return Object.prototype; };
        """)
        expectRejection("return { go: function () {} };", containing: "function")
    }

    func testOverwrittenGetPrototypeOfCannotDisguiseAClassInstance() {
        context.evaluateScript("Object.getPrototypeOf = function () { return Object.prototype; };")
        expectRejection("class C {} return { v: new C() };", containing: "plain")
    }

    // MARK: - Host to JavaScript, and deep freezing

    func testDeepFrozenConfigurationCannotBeMutated() throws {
        let configuration = try bridge.frozenValue(from: [
            "baseURL": "https://example.test",
            "selectors": ["title": ".t"],
            "pages": [1, 2]
        ])
        context.setObject(configuration, forKeyedSubscript: "cfg" as NSString)

        let report = context.evaluateScript("""
            (function () {
              try { cfg.baseURL = "https://evil.test"; } catch (e) {}
              try { cfg.selectors.title = "x"; } catch (e) {}
              try { cfg.pages.push(3); } catch (e) {}
              try { cfg.added = 1; } catch (e) {}
              return [cfg.baseURL, cfg.selectors.title, cfg.pages.length,
                      typeof cfg.added, Object.isFrozen(cfg.selectors)].join("|");
            })()
        """)
        XCTAssertEqual(report?.toString(), "https://example.test|.t|2|undefined|true")
    }

    /// Freezing walks the whole graph with the pristine `Object.freeze`, so an
    /// Extension that replaced it still receives a frozen configuration.
    func testFreezeUsesTheSnapshottedBuiltin() throws {
        context.evaluateScript("Object.freeze = function (o) { return o; };")
        let configuration = try bridge.frozenValue(from: ["a": ["b": 1]])
        context.setObject(configuration, forKeyedSubscript: "cfg" as NSString)
        XCTAssertEqual(context.evaluateScript("Object.isFrozen(cfg.a)")?.toBool(), true)
    }

    func testRoundTripsThroughJavaScript() throws {
        let original: [String: Any] = [
            "items": [["id": "a", "title": "T"]],
            "nextCursor": NSNull(),
            "exhausted": true,
            "limit": 20
        ]
        let injected = try bridge.frozenValue(from: original)
        context.setObject(injected, forKeyedSubscript: "payload" as NSString)
        let value = try bridge.jsonValue(from: context.evaluateScript("payload")!)
        let object = try XCTUnwrap(value as? [String: Any])
        XCTAssertEqual(object["exhausted"] as? Bool, true)
        XCTAssertEqual(object["limit"] as? Int, 20)
        XCTAssertTrue(object["nextCursor"] is NSNull)
        XCTAssertEqual(((object["items"] as? [Any])?.first as? [String: Any])?["id"] as? String, "a")
    }

    /// Converted output feeds the validator S2 built; nothing between them re-checks
    /// JSON compatibility, which is why the check has to be complete here.
    func testConvertedValueIsAcceptedByTheDomainValidator() throws {
        let value = try bridge.jsonValue(from: evaluate("""
            return { items: [{ id: "manga-1", title: "A Title" }], exhausted: true };
        """))
        let validator = ExtensionDomainValidator(assetOrigins: [])
        let page = try validator.validateListingPage(value)
        XCTAssertEqual(page.items.first?.id, "manga-1")
    }
}

/// A Swift object exported to JavaScript — the "host object" the design forbids.
@objc private protocol HostObjectStubExports: JSExport {
    var label: String { get }
}

private final class HostObjectStub: NSObject, HostObjectStubExports {
    let label = "host"
}
