///
module imap.ssl;
import imap.sil : SILdoc;
import std.stdio;
import std.string;
import deimos.openssl.ssl;
import deimos.openssl.err;
import deimos.openssl.x509;
import deimos.openssl.x509_vfy; // needed to use openssl master
import deimos.openssl.pem;
import deimos.openssl.evp;

import imap.defines;
import imap.socket;
import imap.session;

///
enum STDIN_FILENO = 0;

version (Posix) { import core.sys.posix.unistd : isatty; } else {
    // FIXME
    bool isatty(int fileno) {
        return false;
    }
}


///
X509* getPeerCertificate(ref SSL context) {
    import std.exception : enforce;
    X509* cert = SSL_get_peer_certificate(&context);
    enforce(cert, "unable to get peer certificate");
    return cert;
}

@SILdoc("Get SSL/TLS certificate check it, maybe ask user about it and act accordingly.")
Status getCert(ref Session session) {
    import std.exception : enforce;
    X509* pcert = getPeerCertificate(*session.sslConnection);
    enforce(pcert !is null);
    auto cert = pcert;

    scope (exit)
        X509_free(pcert);

    long verify = SSL_get_verify_result(session.sslConnection);
    enforce(((verify == X509_V_OK)
        || (verify == X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT)
        || (verify == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY)),
            format!"certificate verification failed; %d\n"(verify));

    if (verify != X509_V_OK) {
        auto md = cert.getDigest(EVP_md5());
        enforce(checkCert(cert, md) == Status.success, "certificate mismatch occurred");
        enforce(isatty(STDIN_FILENO) != 0, "certificate error: cannot accept certificate in non-interactivemode");
        printCert(cert, md);
        storeCert(cert);
    }
    return Status.success;
}

///
enum Status {
    success,
    failure,
}

@SILdoc("Check if the SSL/TLS certificate exists in the certificates file.")
Status checkCert(X509* pcert, string pmd) {
    import std.file : exists;
    Status status = Status.failure;
    X509* certp;

    string certf = getFilePath("certificates");
    if (!certf.exists())
        return Status.failure;

    auto file = File(certf, "r");
    string pcertSubject = pcert.getSubject();
    string pIssuerName = pcert.getIssuerName();
    string pSerial = pcert.getSerial();

    while ((certp = readX509(file, certp)) !is null) {
        auto cert = certp;
        if (cert.getSubject != pcertSubject || (cert.getIssuerName() != pIssuerName)
            || (cert.getSerial() != pSerial))
            continue;

        auto digest = getDigest(cert, EVP_md5());
        if (digest.length != pmd.length)
            continue;

        if (digest != pmd) {
            status = Status.failure;
            break;
        }
        status = Status.success;
        break;
    }

    X509_free(certp);

    return status;
}

X509* readX509(File file, ref X509* cert) {
    return PEM_read_X509(file.getFP(), &cert, null, null);
}


string getDigest(X509* cert, const(EVP_MD) * type) {
    import std.exception : enforce;
    import std.format : format;
    ubyte[EVP_MAX_MD_SIZE] md;
    uint len;
    auto result = X509_digest(cert, type, md.ptr, &len);
    enforce(result == 1, "failed to get digest for certificate");
    enforce(len > 0, format!"X509_digest returned digest of length: %s"(len));
    return cast(string) (md[0 .. len].idup);
}


///
string getIssuerName(X509* cert) {
    import core.memory : pureFree;
    import std.string : fromStringz;
    char* s = X509_NAME_oneline(X509_get_issuer_name(cert), null, 0);
    scope (exit) pureFree(s);
    return s.fromStringz.idup;
}

///
string getSubject(X509* cert) {
    import core.memory : pureFree;
    import std.string : fromStringz;
    char* s = X509_NAME_oneline(X509_get_subject_name(cert), null, 0);
    scope (exit) pureFree(s);
    return s.fromStringz.idup;
}

///
string asHex(string s) {
    import std.algorithm : map;
    import std.format : format;
    import std.array : array;
    import std.string : join;
    return s.map!(c => format!"%02X"(c)).array.join.idup;
}


@SILdoc("Print information about the SSL/TLS certificate.")
void printCert(X509* cert, string fingerprint) {
    writefln("Server certificate subject: %s", cert.getSubject);
    writefln("Server certificate issuer: %s", getIssuerName(cert));
    writefln("Server certificate serial: %s", cert.getSerial);
    writefln("Server key fingerprint: %s", fingerprint.asHex);
}


@SILdoc("Extract certificate serial number as a string.")
string getSerial(X509* cert) {
    import std.string : fromStringz;
    import std.format : format;
    string buf;

    ASN1_INTEGER* serial = X509_get_serialNumber(cert);
    if (serial.length <= cast(int) long.sizeof) {
        long num = ASN1_INTEGER_get(serial);
        if (serial.type == V_ASN1_NEG_INTEGER) {
            buf ~= format!"-%X"(-num);
        } else {
            buf ~= format!"%X"(num);
        }
    } else {
        if (serial.type == V_ASN1_NEG_INTEGER) {
            buf ~= "-";
        }
        foreach (i; 0 .. serial.length) {
            buf ~= format!"%02X"(serial.data[i]);
        }
    }
    return buf;
}


@SILdoc("Store the SSL/TLS certificate after asking the user to accept/reject it.")
void storeCert(X509* cert) {
    import std.string : toLower;
    import std.stdio : stdin, writef, File;
    import core.memory : pureFree;
    import std.range : front;
    import std.conv : to;
    import std.exception : enforce;

    char c;
    do {
        writef("(R)eject, accept (t)emporarily or accept (p)ermanently? ");
        do {} while (stdin.eof);
        c = stdin.rawRead(new char[1]).toLower.front.to!char;
    } while (c != 'r' && c != 't' && c != 'p');

    enforce(c != 'r', "certificate rejected");
    if (c == 't')
        return;
    auto certf = getFilePath("certificates");
    auto file  = File(certf, "a");
    char* s = X509_NAME_oneline(X509_get_subject_name(cert), null, 0);
    file.writefln("Subject: %s", s);
    pureFree(s);
    s = X509_NAME_oneline(X509_get_issuer_name(cert), null, 0);
    file.writefln("Issuer: %s", s);
    pureFree(s);
    auto serialNo = getSerial(cert);
    file.writefln("Serial: %s", serialNo);

    PEM_write_X509(file.getFP(), cert);

    file.writefln("");
}

///
string getFilePath(string subDir) {
    import std.path : expandTilde, dirSeparator;
    return expandTilde("~" ~ dirSeparator ~ subDir);
}

void loadVerifyLocations(SSL_CTX* ctx, string caFile, string caPath) {
    import std.exception : enforce;
    auto ret = SSL_CTX_load_verify_locations(ctx, caFile.toStringz, caPath.toStringz);
    enforce(ret == 0, "SSL unable to load verify locations");
}

void setDefaultVerifyPaths(SSL_CTX* ctx) {
    import std.exception : enforce;
    auto ret = SSL_CTX_set_default_verify_paths(ctx);
    enforce(ret == 0, "SSL unable to set default verify paths");
}
