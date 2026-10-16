import Foundation
import TableProMSSQLCore
import TableProPluginKit

/// The FreeTDS encryption level and certificate checks behind each SSL mode. libtds reads both from the connection's
/// freetds.conf entry and from nowhere else; see MSSQLFreeTDSServerEntry.
///
/// Disabled asks for `off`: the client tells the server it cannot encrypt at all, so the whole session — including
/// the login — runs over plain TCP. This is the only option that reaches legacy servers whose TLS cannot
/// interoperate with modern clients. Preferred keeps the SQL Server driver convention, `request`: the login is
/// encrypted and the rest of the session is not, unless the server forces encryption.
enum MSSQLSSLMapping {
    static func encryptionLevel(for mode: SSLMode) -> MSSQLEncryptionLevel {
        switch mode {
        case .disabled: return .off
        case .preferred: return .request
        case .required, .verifyCa, .verifyIdentity: return .require
        }
    }

    static func certificateVerification(for mode: SSLMode) -> MSSQLCertificateVerification {
        switch mode {
        case .disabled, .preferred, .required: return .none
        case .verifyCa: return .chain
        case .verifyIdentity: return .chainAndHostname
        }
    }
}
