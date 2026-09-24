import Foundation
import Security

public struct CodeSignatureInfo: Equatable, Sendable {
    public let teamIdentifier: String
    public let designatedRequirement: String
    public let isDeveloperID: Bool

    public init(
        teamIdentifier: String,
        designatedRequirement: String,
        isDeveloperID: Bool = true
    ) {
        self.teamIdentifier = teamIdentifier
        self.designatedRequirement = designatedRequirement
        self.isDeveloperID = isDeveloperID
    }
}

public enum CodeSignatureValidationError: Error, Equatable {
    case cannotCreateStaticCode(OSStatus)
    case invalidSignature(OSStatus)
    case unsignedOrAdHoc
    case cannotCreateAppleAnchorRequirement(OSStatus)
    case notAppleAnchored(OSStatus)
    case missingTeamIdentifier
    case missingDesignatedRequirement(OSStatus)
}

public protocol CodeSignatureValidating: Sendable {
    func validateCode(at url: URL) throws -> CodeSignatureInfo
}

public struct SecurityCodeSignatureValidator: CodeSignatureValidating, Sendable {
    public init() {}

    public func validateCode(at url: URL) throws -> CodeSignatureInfo {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw CodeSignatureValidationError.cannotCreateStaticCode(createStatus)
        }
        let validity = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
            nil
        )
        guard validity == errSecSuccess else {
            throw CodeSignatureValidationError.invalidSignature(validity)
        }
        var appleAnchor: SecRequirement?
        let anchorStatus = SecRequirementCreateWithString("anchor apple generic" as CFString, [], &appleAnchor)
        guard anchorStatus == errSecSuccess, let appleAnchor else {
            throw CodeSignatureValidationError.cannotCreateAppleAnchorRequirement(anchorStatus)
        }
        let anchorValidity = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
            appleAnchor
        )
        guard anchorValidity == errSecSuccess else {
            throw CodeSignatureValidationError.notAppleAnchored(anchorValidity)
        }
        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard infoStatus == errSecSuccess,
              let dictionary = information as? [CFString: Any],
              let teamID = dictionary[kSecCodeInfoTeamIdentifier] as? String,
              !teamID.isEmpty
        else { throw CodeSignatureValidationError.missingTeamIdentifier }
        // CS_ADHOC from <Security/CodeSigning.h> is not imported into Swift.
        let adHocSignatureFlag: UInt32 = 0x0000_0002
        if let flags = dictionary[kSecCodeInfoFlags] as? NSNumber,
           flags.uint32Value & adHocSignatureFlag != 0 {
            throw CodeSignatureValidationError.unsignedOrAdHoc
        }
        var requirement: SecRequirement?
        let requirementStatus = SecCodeCopyDesignatedRequirement(staticCode, [], &requirement)
        guard requirementStatus == errSecSuccess, let requirement else {
            throw CodeSignatureValidationError.missingDesignatedRequirement(requirementStatus)
        }
        var requirementText: CFString?
        let textStatus = SecRequirementCopyString(requirement, [], &requirementText)
        guard textStatus == errSecSuccess, let requirementText else {
            throw CodeSignatureValidationError.missingDesignatedRequirement(textStatus)
        }
        var developerIDRequirement: SecRequirement?
        let developerIDStatus = SecRequirementCreateWithString(
            "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" as CFString,
            [],
            &developerIDRequirement
        )
        let isDeveloperID = developerIDStatus == errSecSuccess
            && developerIDRequirement.map {
                SecStaticCodeCheckValidity(
                    staticCode,
                    SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
                    $0
                ) == errSecSuccess
            } == true
        return CodeSignatureInfo(
            teamIdentifier: teamID,
            designatedRequirement: requirementText as String,
            isDeveloperID: isDeveloperID
        )
    }
}
