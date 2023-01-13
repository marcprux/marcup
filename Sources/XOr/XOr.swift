/**
 Copyright (c) 2015-2023 Marc Prud'hommeaux
 */
import Swift

/// The basis of one of multiple possible types, equivalent to an
/// `Either` sum type.
///
/// A choice between two different types is expressed by `XOr<P>.Or<Q>`.
/// For example:
///
/// ```
/// let stringOrInt: XOr<String>.Or<Int>
/// ```
///
/// Additional types can be expressed by chaining `Or` types.
/// ```
/// let stringOrIntOrBool: XOr<String>.Or<Int>.Or<Bool>
/// let dateOrURLOrDataOrUUID: XOr<Date>.Or<URL>.Or<Data>.Or<UUID>
/// ```
///
/// `XOr.Or` adopts `Codable` when its associated types adopt `Codable`.
/// Decoding is accomplished by trying to decode each encapsulated
/// type separately and accepting the first successfully decoded result.
///
/// This can present an issue for types that can encode to the same serialized data,
/// such as `XOr<Double>.Or<Float>`, since encoded the `Float` side will then
/// be decoded as the `Double` side, which might be unexpected since it will
/// fail an equality check. To work around this, the encapsulated types
/// would need a type discriminator field to ensure that both sides
/// are mutually exclusive for decoding.
///
/// In short, given `typealias DoubleOrFloat = XOr<Double>.Or<Float>`: `try DoubleOrFloat(Float(1.0)).encoded().decoded() != DoubleOrFloat(Float(1.0))`
public indirect enum XOr<P> : RawRepresentable {
    public typealias Value = P
    case p(P)

    public var rawValue: P {
        get {
            switch self {
            case .p(let value): return value
            }
        }

        set {
            self = .p(newValue)
        }
    }

    public init(rawValue: P) { self = .p(rawValue) }
    public init(_ rawValue: P) { self = .p(rawValue) }

    /// A sum type: `XOr<P>.Or<Q>` can hold either an `P` or a `Q`.
    /// E.g., `XOr<Int>.Or<String>.Or<Bool>` can hold either an `Int` or a `String` or a `Bool`
    public indirect enum Or<Q> : XOrType {
        public typealias P = Value
        public typealias Q = Q
        public typealias Or<R> = XOr<P>.Or<XOr<Q>.Or<R>>

        case p(P)
        case q(Q)

        public init(_ p: P) { self = .p(p) }
        public init(_ q: Q) { self = .q(q) }

        public var p: P? { infer() }
        public var q: Q? { infer() }

        @inlinable public func infer() -> P? {
            if case .p(let p) = self { return p } else { return nil }
        }

        @inlinable public func infer() -> Q? {
            if case .q(let q) = self { return q } else { return nil }
        }
    }
}

extension XOr.Or {
    /// Maps each side of an `XOr.Or` through the given function
    @inlinable public func map<T, U>(_ pf: (P) -> T, _ qf: (Q) -> U) -> XOr<T>.Or<U> {
        switch self {
        case .p(let p): return .p(pf(p))
        case .q(let q): return .q(qf(q))
        }
    }
}

extension XOr.Or {
    /// Returns a flipped view of the `XOr.Or`, where `P` becomes `Q` and `Q` becomes `P`.
    @inlinable public var swapped: XOr<Q>.Or<P> {
        get {
            switch self {
            case .p(let p): return .q(p)
            case .q(let q): return .p(q)
            }
        }

        set {
            switch newValue {
            case .p(let p): self = .q(p)
            case .q(let q): self = .p(q)
            }
        }
    }
}

extension XOr.Or where P == Q {
    /// The underlying read-only value of either p or q
    @inlinable public var value: P {
        get {
            switch self {
            case .p(let p): return p
            case .q(let q): return q
            }
        }
    }

    /// The underlying value of the p or q, when `P == Q`, where mutation always sets `.p`.
    @inlinable public var pvalue: P {
        get {
            switch self {
            case .p(let p): return p
            case .q(let q): return q
            }
        }

        set {
            self = .p(newValue)
        }
    }

    /// The underlying value of the p or q, when `P == Q`, where mutation always sets `.q`.
    @inlinable public var qvalue: P {
        get {
            switch self {
            case .q(let q): return q
            case .p(let p): return p
            }
        }

        set {
            self = .q(newValue)
        }
    }
}

extension XOr : Equatable where P : Equatable { }
extension XOr.Or : Equatable where P : Equatable, Q : Equatable { }

extension XOr : Hashable where P : Hashable { }
extension XOr.Or : Hashable where P : Hashable, Q : Hashable { }

extension XOr : Encodable where P : Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

extension XOr.Or : Encodable where P : Encodable, Q : Encodable {
    public func encode(to encoder: Encoder) throws {
        // we differ from the default Encodable behavior of enums in that we encode the underlying values directly, without referencing the case names
        var container = encoder.singleValueContainer()
        switch self {
        case .p(let x): try container.encode(x)
        case .q(let x): try container.encode(x)
        }
    }
}


extension XOr : Decodable where P : Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let element = try container.decode(P.self)
        self.init(rawValue: element)
    }
}

extension XOr.Or : Decodable where P : Decodable, Q : Decodable {
    /// `XOr.Or` implements decodable for brute-force trying to decode first `A` and then `B`
    public init(from decoder: Decoder) throws {
        do {
            self = try .p(.init(from: decoder))
        } catch let e1 {
            do {
                self = try .q(.init(from: decoder))
            } catch let e2 {
                throw XOrDecodingError(e1: e1, e2: e2)
            }
        }
    }

    /// An error that occurs when decoding fails for an `XOr` type.
    /// This encapsulates all the errors that resulted in the decode arrempt.
    public struct XOrDecodingError : Error {
        public let e1, e2: Error
    }
}

extension XOr : Error where P : Error { }
extension XOr.Or : Error where P : Error, Q : Error { }

extension XOr : Sendable where P : Sendable { }
extension XOr.Or : Sendable where P : Sendable, Q : Sendable { }


/// A `OneOrMany` is either a single element or a sequence of elements
public typealias ElementOrSequence<Seq: Sequence> = XOr<Seq.Element>.Or<Seq>

/// A `OneOrMany` is either a single value or any array of zero or multiple values
public typealias ElementOrArray<Element> = ElementOrSequence<Array<Element>>

extension ElementOrSequence : ExpressibleByArrayLiteral where Q : RangeReplaceableCollection, Q.Element == P {
    /// Initialized this sequence with either a single element or mutiple elements depending on the array contents.
    public init(arrayLiteral elements: Q.Element...) {
        self = elements.count == 1 ? .p(elements[0]) : .q(.init(elements))
    }
}

extension ElementOrSequence where Q : Collection, Q : ExpressibleByArrayLiteral, P == Q.ArrayLiteralElement, P == Q.Element {

    /// The number of elements in .q; .p always returns 1
    public var count: Int {
        switch self {
        case .p: return 1
        case .q(let x): return x.count
        }
    }

    /// The array of instances, whose setter will opt for the single option
    public var collectionSingle: Q {
        get { map({ p in Q(arrayLiteral: p) }, { q in q }).value }
        set { self = newValue.count == 1 ? .p(newValue.first!) : .q(newValue) }
    }

    /// The array of instances, whose setter will opt for the multiple option
    public var collectionMulti: Q {
        get { map({ p in Q(arrayLiteral: p) }, { q in q }).value }
        set { self = .q(newValue) }
    }
}

/// An `XResult` is similar to a `Foundation.Result` except it uses `XOr` arity
public typealias XResult<Success, Failure: Error> = XOr<Failure>.Or<Success>

public extension XResult where P : Error {
    typealias Success = Q
    typealias Failure = P

    /// An `XOr` whose first element is an error type can be converted to a `Result`.
    /// Note that the arity is the opposite of `Result`: `XOr`'s first type will be `Error`.
    @inlinable var result: Result<Success, Failure> {
        get {
            switch self {
            case .p(let error): return .failure(error)
            case .q(let value): return .success(value)
            }
        }

        set {
            switch newValue {
            case .success(let value): self = .q(value)
            case .failure(let error): self = .p(error)
            }
        }
    }

    /// Unwraps the success value or throws a failure if it is an error
    @inlinable func get() throws -> Q {
        try result.get()
    }
}

// MARK: Inferrence support

public protocol XOrType {
    associatedtype P
    init(_ rawValue: P)
    /// If this type wraps a `P`
    func infer() -> P?

    associatedtype Q
    init(_ rawValue: Q)
    /// If this type wraps a `Q`
    func infer() -> Q?
}

extension XOr.Or where Q : XOrType {
    public init(_ rawValue: Q.P) { self = .init(.init(rawValue)) }
    public init(_ rawValue: Q.Q) { self = .init(.init(rawValue)) }

    /// `Q.P` if that is the case
    public func infer() -> Q.P? { infer()?.infer() }
    /// `Q.Q` if that is the case
    public func infer() -> Q.Q? { infer()?.infer() }
}

extension XOr.Or where Q : XOrType, Q.P : XOrType {
    public init(_ rawValue: Q.P.P) { self = .init(.init(.init(rawValue))) }
    public init(_ rawValue: Q.P.Q) { self = .init(.init(.init(rawValue))) }

    /// `Q.P.P` if that is the case
    public func infer() -> Q.P.P? { infer()?.infer()?.infer() }
    /// `Q.P.Q` if that is the case
    public func infer() -> Q.P.Q? { infer()?.infer()?.infer() }
}

extension XOr.Or where Q : XOrType, Q.Q : XOrType {
    public init(_ rawValue: Q.Q.P) { self = .init(.init(.init(rawValue))) }
    public init(_ rawValue: Q.Q.Q) { self = .init(.init(.init(rawValue))) }

    /// `Q.Q.P` if that is the case
    public func infer() -> Q.Q.P? { infer()?.infer()?.infer() }
    /// `Q.Q.Q` if that is the case
    public func infer() -> Q.Q.Q? { infer()?.infer()?.infer() }
}

// … and so on …