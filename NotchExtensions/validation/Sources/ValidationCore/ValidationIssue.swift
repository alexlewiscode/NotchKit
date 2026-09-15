//
//  ValidationIssue.swift
//  ValidationCore
//
//  The result type shared by the library and the `ext-validate` CLI.
//

import Foundation

/// How serious an issue is.
///
/// Only `.error` issues change the CLI exit code. Warnings are informational and
/// never fail validation.
public enum ValidationSeverity: String, Equatable, Sendable {
    case error
    case warning
}

/// Which stage of validation produced an issue.
///
/// `.structural` issues describe a manifest that is not a well-formed, strict
/// instance of the canonical schema. `.hostCompatibility` issues describe a
/// structurally valid manifest that the running host/SDK cannot run.
public enum ValidationPhase: String, Equatable, Sendable {
    case structural
    case hostCompatibility
}

/// A single validation finding.
public struct ValidationIssue: Equatable, Sendable {
    /// How serious the issue is.
    public let severity: ValidationSeverity
    /// Which validation stage produced the issue.
    public let phase: ValidationPhase
    /// A stable, machine-readable identifier for the issue kind.
    public let code: String
    /// A human-readable explanation.
    public let message: String
    /// A JSON path (for example `$.entryPoints[0].kind`) when one applies.
    public let path: String?

    public init(
        severity: ValidationSeverity,
        phase: ValidationPhase,
        code: String,
        message: String,
        path: String? = nil
    ) {
        self.severity = severity
        self.phase = phase
        self.code = code
        self.message = message
        self.path = path
    }
}
