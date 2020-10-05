///
module imap.auth;
import imap.sil : SILdoc;
import std.string;
import std.stdio;
import deimos.openssl.ssl;
import deimos.openssl.hmac;
import deimos.openssl.evp;
import imap.defines;


@SILdoc("challenge-response authentication mechanism MD5")
string authCramMD5(string user, string pass, string challenge) {
    import std.conv : to;
    import std.algorithm : map;
    import std.array : array;
    import std.string : join;
    import std.format : format;
    size_t n;
    uint i;
    ubyte[] resp, ret;
    ubyte[EVP_MAX_MD_SIZE] md;
    uint mdlen;
    HMAC_CTX hmac;

    n = challenge.length * 3 / 4 + 1;
    resp.length = n;
    EVP_DecodeBlock(resp.ptr, cast(const(ubyte) *) challenge.toStringz, challenge.length.to!int);

    HMAC_Init(&hmac, cast(const(void) *) pass.toStringz, pass.length.to!int, EVP_md5());
    HMAC_Update(&hmac, cast(const(ubyte) *) resp.ptr, resp.length.to!int);
    HMAC_Final(&hmac, md.ptr, &mdlen);

    auto mdhex = md[0 .. mdlen]
        .map!(c => format!"%02X"(c)).array.join("");
    auto buf = format!"%s %s"(user, mdhex);
    n = (buf.length + 3) * 4 / 3 + 1;
    ret.length = n;
    EVP_EncodeBlock(ret.ptr, cast(ubyte*) buf.ptr, buf.length.to!int);
    return cast(string) (ret.idup);
}
