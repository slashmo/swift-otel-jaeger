//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift OpenTelemetry open source project
//
// Copyright (c) 2021 Moritz Lang and the Swift OpenTelemetry project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Instrumentation
@testable import OpenTelemetryJaeger
import XCTest

final class PropagatorTests: XCTestCase {
    private let propagator = JaegerPropagator()
    private let injector = DictionaryInjector()
    private let extractor = DictionaryExtractor()

    // MARK: - Inject

    func test_injectsTraceIDHeader_notSampled() {
        let spanContext = OTel.SpanContext(
            traceID: .stub,
            spanID: .stub,
            traceFlags: [],
            isRemote: false
        )
        var headers = [String: String]()

        propagator.inject(spanContext, into: &headers, using: injector)

        XCTAssertEqual(
            headers,
            ["uber-trace-id": "0102030405060708090a0b0c0d0e0f10:0102030405060708:0:0"]
        )
    }

    func test_injectsTraceIDHeader_sampled() {
        let spanContext = OTel.SpanContext(
            traceID: .stub,
            spanID: .stub,
            traceFlags: .sampled,
            isRemote: false
        )
        var headers = [String: String]()

        propagator.inject(spanContext, into: &headers, using: injector)

        XCTAssertEqual(
            headers,
            ["uber-trace-id": "0102030405060708090a0b0c0d0e0f10:0102030405060708:0:1"]
        )
    }

    // MARK: - Extract

    func test_extractsNil_withoutTraceIDHeader() throws {
        let headers = ["Content-Type": "application/json"]

        XCTAssertNil(try propagator.extractSpanContext(from: headers, using: extractor))
    }

    func test_extractsTraceIDHeader_notSampled() throws {
        let headers = ["uber-trace-id": "0102030405060708090a0b0c0d0e0f10:0102030405060708:0:0"]

        let spanContext = try XCTUnwrap(propagator.extractSpanContext(from: headers, using: extractor))

        XCTAssertEqual(spanContext.traceID, .stub)
        XCTAssertEqual(spanContext.spanID, .stub)
        XCTAssertTrue(spanContext.traceFlags.isEmpty)
        XCTAssertNil(spanContext.traceState)
    }

    func test_extractsTraceIDHeader_sampled() throws {
        let headers = ["uber-trace-id": "0102030405060708090a0b0c0d0e0f10:0102030405060708:0:1"]

        let spanContext = try XCTUnwrap(propagator.extractSpanContext(from: headers, using: extractor))

        XCTAssertEqual(spanContext.traceID, .stub)
        XCTAssertEqual(spanContext.spanID, .stub)
        XCTAssertEqual(spanContext.traceFlags, .sampled)
        XCTAssertNil(spanContext.traceState)
    }

    func test_extractsTraceIDHeader_paddedTraceID() throws {
        let headers = ["uber-trace-id": "0102030405060708:0102030405060708:0:1"]

        let spanContext = try XCTUnwrap(propagator.extractSpanContext(from: headers, using: extractor))

        XCTAssertEqual(spanContext.traceID, OTel.TraceID(bytes: (0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)))
        XCTAssertEqual(spanContext.spanID, .stub)
        XCTAssertEqual(spanContext.traceFlags, .sampled)
        XCTAssertNil(spanContext.traceState)
    }

    func test_extractsTraceIDHeader_paddedSpanID() throws {
        let headers = ["uber-trace-id": "0102030405060708090a0b0c0d0e0f10:01020304:0:1"]

        let spanContext = try XCTUnwrap(propagator.extractSpanContext(from: headers, using: extractor))

        XCTAssertEqual(spanContext.traceID, .stub)
        XCTAssertEqual(spanContext.spanID, OTel.SpanID(bytes: (0, 0, 0, 0, 1, 2, 3, 4)))
        XCTAssertEqual(spanContext.traceFlags, .sampled)
        XCTAssertNil(spanContext.traceState)
    }

    func test_extractThrows_tooFewComponents() throws {
        let headers = ["uber-trace-id": "0102030405060708090a0b0c0d0e0f10:1"]

        XCTAssertThrowsError(
            try propagator.extractSpanContext(from: headers, using: extractor),
            JaegerPropagator.TraceIDHeaderParsingError(
                value: "0102030405060708090a0b0c0d0e0f10:1",
                reason: .invalidNumberOfComponents(2)
            )
        )
    }

    func test_extractThrows_tooManyComponents() throws {
        let headers = ["uber-trace-id": "0102030405060708090a0b0c0d0e0f10:0102030405060708:0102030405060708:0:1"]

        XCTAssertThrowsError(
            try propagator.extractSpanContext(from: headers, using: extractor),
            JaegerPropagator.TraceIDHeaderParsingError(
                value: "0102030405060708090a0b0c0d0e0f10:0102030405060708:0102030405060708:0:1",
                reason: .invalidNumberOfComponents(5)
            )
        )
    }

    func test_extractThrows_traceIDTooLong() throws {
        let traceID = "0102030405060708090a0b0c0d0e0f100102030405060708090a0b0c0d0e0f10"
        let header = "\(traceID):0102030405060708:0:1"
        let headers = ["uber-trace-id": header]

        XCTAssertThrowsError(
            try propagator.extractSpanContext(from: headers, using: extractor),
            JaegerPropagator.TraceIDHeaderParsingError(value: traceID, reason: .traceIDTooLong(64))
        )
    }

    func test_extractThrows_spanIDTooLong() throws {
        let spanID = "01020304050607080102030405060708"
        let header = "0102030405060708090a0b0c0d0e0f10:\(spanID):0:1"
        let headers = ["uber-trace-id": header]

        XCTAssertThrowsError(
            try propagator.extractSpanContext(from: headers, using: extractor),
            JaegerPropagator.TraceIDHeaderParsingError(value: spanID, reason: .spanIDTooLong(32))
        )
    }
}

private struct DictionaryInjector: Injector {
    init() {}

    func inject(_ value: String, forKey key: String, into carrier: inout [String: String]) {
        carrier[key] = value
    }
}

private struct DictionaryExtractor: Extractor {
    init() {}

    func extract(key: String, from carrier: [String: String]) -> String? {
        carrier[key]
    }
}

extension OTel.TraceID {
    static let stub = OTel.TraceID(bytes: (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16))
}

extension OTel.SpanID {
    static let stub = OTel.SpanID(bytes: (1, 2, 3, 4, 5, 6, 7, 8))
}
