#!/usr/bin/env swift

import CryptoKit
import Foundation

/// Verifies that a Sparkle EdDSA signature was made by the public key embedded
/// in Uttr. This is deliberately independent of the private signing key so CI
/// catches a mismatched GitHub secret before it publishes an appcast.
enum VerificationError: LocalizedError {
    case usage
    case invalidBase64(String)
    case invalidPublicKey
    case invalidSignature
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: verify-sparkle-signature.swift <public-key-base64> <signature-base64> <archive>"
        case .invalidBase64(let name):
            return "The \(name) is not valid base64."
        case .invalidPublicKey:
            return "The Sparkle public key is not a valid Ed25519 public key."
        case .invalidSignature:
            return "The Sparkle signature is not a valid Ed25519 signature."
        case .verificationFailed:
            return "The Sparkle signature does not validate this archive with the embedded public key."
        }
    }
}

func requiredData(_ base64: String, named name: String) throws -> Data {
    guard let data = Data(base64Encoded: base64) else {
        throw VerificationError.invalidBase64(name)
    }
    return data
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 else { throw VerificationError.usage }

    let publicKeyData = try requiredData(arguments[1], named: "public key")
    let signature = try requiredData(arguments[2], named: "signature")
    guard signature.count == 64 else { throw VerificationError.invalidSignature }

    let publicKey: Curve25519.Signing.PublicKey
    do {
        publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    } catch {
        throw VerificationError.invalidPublicKey
    }

    let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[3]), options: .mappedIfSafe)
    guard publicKey.isValidSignature(signature, for: archive) else {
        throw VerificationError.verificationFailed
    }
    print("Sparkle archive signature verified against the embedded public key.")
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
