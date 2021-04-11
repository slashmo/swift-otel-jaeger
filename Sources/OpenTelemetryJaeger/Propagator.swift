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
@_exported import OpenTelemetry

/// An OTelPropagator that propagates span context through the 'uber-trace-id' header.
///
/// - SeeAlso: [Jaeger Propagation Format](https://www.jaegertracing.io/docs/1.22/client-libraries/#propagation-format)
public struct JaegerPropagator: OTelPropagator {
    /// Initialize a Jaeger compatible propagator.
    public init() {}

    public func inject<Carrier, Inject>(
        _ spanContext: OTel.SpanContext,
        into carrier: inout Carrier,
        using injector: Inject
    ) where Inject: Injector, Carrier == Inject.Carrier {
        let header = [
            String(describing: spanContext.traceID),
            String(describing: spanContext.spanID),
            "0", // deprecated span-id
            spanContext.traceFlags.contains(.sampled) ? "1" : "0",
        ].joined(separator: ":")

        injector.inject(header, forKey: "uber-trace-id", into: &carrier)
    }

    public func extractSpanContext<Carrier, Extract>(
        from carrier: Carrier,
        using extractor: Extract
    ) throws -> OTel.SpanContext? where Extract: Extractor, Carrier == Extract.Carrier {
        guard let header = extractor.extract(key: "uber-trace-id", from: carrier) else { return nil }
        let parts = header.split(separator: ":")
        guard parts.count == 4 else {
            throw TraceIDHeaderParsingError(value: header, reason: .invalidNumberOfComponents(parts.count))
        }
        let traceID = try extractTraceID(parts[0])
        let spanID = try extractSpanID(parts[1])

        let traceFlagsString = parts[3]
        let traceFlags: OTel.TraceFlags = traceFlagsString == "1" ? .sampled : []

        return OTel.SpanContext(traceID: traceID, spanID: spanID, traceFlags: traceFlags, isRemote: true)
    }

    private func extractTraceID<S: StringProtocol>(_ string: S) throws -> OTel.TraceID {
        guard string.count <= 32 else {
            throw TraceIDHeaderParsingError(value: String(string), reason: .traceIDTooLong(string.count))
        }
        let traceIDString = string.count == 32
            ? String(string)
            : String(repeating: "0", count: 32 - string.count) + string

        let traceID = traceIDString.utf8.withContiguousStorageIfAvailable { traceIDBytes -> OTel.TraceID in
            var traceIDStorage: OTel.TraceID.Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            withUnsafeMutableBytes(of: &traceIDStorage) { OTel.Hex.convert(traceIDBytes, toBytes: $0) }
            return OTel.TraceID(bytes: traceIDStorage)
        }

        return try traceID ?? extractTraceID(String(string))
    }

    private func extractSpanID<S: StringProtocol>(_ string: S) throws -> OTel.SpanID {
        guard string.count <= 16 else {
            throw TraceIDHeaderParsingError(value: String(string), reason: .spanIDTooLong(string.count))
        }
        let spanIDString = string.count == 16
            ? String(string)
            : String(repeating: "0", count: 16 - string.count) + string

        let spanID = spanIDString.utf8.withContiguousStorageIfAvailable { spanIDBytes -> OTel.SpanID in
            var spanIDStorage: OTel.SpanID.Bytes = (0, 0, 0, 0, 0, 0, 0, 0)
            withUnsafeMutableBytes(of: &spanIDStorage) { OTel.Hex.convert(spanIDBytes, toBytes: $0) }
            return OTel.SpanID(bytes: spanIDStorage)
        }

        return try spanID ?? extractSpanID(String(string))
    }
}

public extension JaegerPropagator {
    struct TraceIDHeaderParsingError: Error, Equatable {
        public let value: String
        public let reason: Reason
    }
}

public extension JaegerPropagator.TraceIDHeaderParsingError {
    enum Reason: Equatable {
        case invalidNumberOfComponents(Int)
        case traceIDTooLong(Int)
        case spanIDTooLong(Int)
    }
}
