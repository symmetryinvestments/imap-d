///
module imap.namespace;
import std.conv : to;

enum UNICODE_REPLACEMENT_CHAR = to!int ("fffd", 16);

// Characters >= base require surrogates
enum UTF16_SURROGATE_BASE = to!int ("10000", 16);

enum UTF16_SURROGATE_SHIFT = 10;
enum UTF16_SURROGATE_MASK = to!int ("03ff", 16);
enum UTF16_SURROGATE_HIGH_FIRST = to!int ("d800", 16);
enum UTF16_SURROGATE_HIGH_LAST = to!int ("dbff", 16);
enum UTF16_SURROGATE_HIGH_MAX = to!int ("dfff", 16);
enum UTF16_SURROGATE_LOW_FIRST = to!int ("dc00", 16);
enum UTF16_SURROGATE_LOW_LAST = to!int ("dfff", 16);

auto UTF16_SURROGATE_HIGH(T : int)(T chr) {
    return UTF16_SURROGATE_HIGH_FIRST
    + (((chr) - UTF16_SURROGATE_BASE) >> UTF16_SURROGATE_SHIFT);
}

auto UTF16_SURROGATE_LOW(T : int)(T chr) {
    return UTF16_SURROGATE_LOW_FIRST
           + (((chr) - UTF16_SURROGATE_BASE) & UTF16_SURROGATE_MASK);
}

enum UTF8_REPLACEMENT_CHAR_LEN = 3;

char Hex(string s)() {
    import std.range : front;
    import std.conv : to;
    return s.to!int (16).to!char;
    // static assert(ret.length == 1, "cannot convert " ~ s ~ "to a single character");
    // return ret; // .front; // .to!char;
}

immutable Base64EncodeTable = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+,";
immutable Base64DecodeTable = parseBase64DecodeTable(`
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,62, 63,XX,XX,XX,
	52,53,54,55, 56,57,58,59, 60,61,XX,XX, XX,XX,XX,XX,
	XX, 0, 1, 2,  3, 4, 5, 6,  7, 8, 9,10, 11,12,13,14,
	15,16,17,18, 19,20,21,22, 23,24,25,XX, XX,XX,XX,XX,
	XX,26,27,28, 29,30,31,32, 33,34,35,36, 37,38,39,40,
	41,42,43,44, 45,46,47,48, 49,50,51,XX, XX,XX,XX,XX,
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
	XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX
`);

string parseBase64DecodeTable(string s) {
    import std.string : replace, split, strip;
    import std.conv : to;
    import std.algorithm : map;
    import std.array : array;

    return
        s.replace("XX", "FF")
        .split(',')
        .map!(tok => tok.strip.to!int (16).to!char)
        .array
        .to!string;
}


private char lookup(alias Table, Number : int)(Number c) {
// if (is(Number == int) || is(Number == char))
    import std.conv : to;
    import std.exception : enforce;
    enforce(c >= 0 && c < Table.length, "index error in lookup in " ~ Table.stringof ~ " for char: " ~ c.to!int.to!string);
    return Table[c].to!char;
}


string modifiedBase64Encode(string src) {
    import std.array : Appender;
    import std.conv : to;
    Appender!string ret;
    ret.put('&');
    while (src.length >= 3) {
        ret.put(lookup!Base64EncodeTable(src[0] >> 2));
        ret.put(lookup!Base64EncodeTable(((src[0] & 3) << 4) | (src[1] >> 4)).to!char);
        ret.put(lookup!Base64EncodeTable(((src[1] & Hex!"0f") << 2) | ((src[2] & Hex!"c0") >> 6)).to!char);
        ret.put(lookup!Base64EncodeTable(src[2] & Hex!"3f"));
        src = src[3 .. $];
    }
    if (src.length > 0) {
        ret.put(lookup!Base64EncodeTable(src[0] >> 2));
        if (src.length == 1) {
            ret.put(lookup!Base64EncodeTable((src[0] & Hex!"03") << 4));
        } else {
            ret.put(lookup!Base64EncodeTable(((src[0] & Hex!"03") << 4) | (src[1] >> 4)));
            ret.put(lookup!Base64EncodeTable((src[1] & Hex!"0f") << 2));
        }
    }
    ret.put('-');
    return ret.data;
}

string imapUtf8FirstEncodeSubstring(string s) {
    string ret;
    foreach (i, c; s) {
        if (c == '&' || (c < Hex!"020") || (c > Hex!"07f"))
            return s[i .. $];
    }
    return null;
}

/// Convert a unicode mailbox name to the modified UTF-7 encoding, according to RFC 3501 Section 5.1.3.
string utf8ToUtf7(string src) {
    import std.array : Appender;
    import std.conv : to;

    Appender!string ret;
    auto p = imapUtf8FirstEncodeSubstring(src);
    if (p.length == 0) // no characters to be encoded
        return src;

    // at least one encoded character
    ret.put(src[src.length - p.length]);
    size_t i = 0;
    while (i < src.length) {
        auto c = src[i];
        if (c == '&') {
            ret.put("&-");
            continue;
        }
        if (c >= Hex!"020" && c < Hex!"07f") {
            ret.put(c);
            continue;
        }

        Appender!string u;
        while (i < src.length && src[i] < Hex!"20" && src[i] >= Hex!"7f") {
            auto chr = utf8GetChar(src[i .. $]);
            if (chr < UTF16_SURROGATE_BASE) {
                u.put((chr >> 8).to!char);
                u.put((chr & Hex!"ff").to!char);
            } else {
                auto u16 = UTF16_SURROGATE_HIGH(chr);
                u.put((u16 >> 8).to!char);
                u.put((u16 & Hex!"ff").to!char);
                u16 = UTF16_SURROGATE_LOW(chr);
                u.put((u16 >> 8).to!char);
                u.put((u16 & Hex!"ff").to!char);
            }
            i += utf8CharBytes(src[c]);
        }
        ret.put(modifiedBase64Encode(u.data));
    }
    return ret.data;
}

bool isValidUtf7(dchar c) {
    return c >= Hex!"020" && c < Hex!"7f";
}

string utf16BufToUtf8(char[] output, uint pos_) {
    import std.exception : enforce;
    uint pos = pos_;
    ushort high, low;
    char chr;
/+
    enforce(output.length <=4, "utf16BufToUtf8 requires input <= 4 chars, not " ~ output.length.to!string);
    if (output.length % 2 != 0)
        return null;

    high = (output[pos %4] << 8) | output[(pos+1) % 4];
    if (high < UTF16_SURROGATE_HIGH_FIRST || high > UTF16_SURROGATE_HIGH_MAX)
    {
        // single byte
        size_t oldlen = ret.length;
        uni_ucs4_to_utf8_c(high,dest);
        if (dest.length - oldlen == 1)
        {
            char last =
                +/
    return "";
}

string modifiedBase64DecodeToUtf8(string src) {
    import std.conv : to;
    import std.array : Appender;
    Appender!string ret;
    char[4] input, output;
    uint outstart, outpos;

    size_t i = 0;
    while ((src.length > i) && src[i] != '-') {
        input[0] = lookup!Base64DecodeTable(src[i]);
        if (input[0] == Hex!"ff")
            return null;
        input[0] = lookup!Base64DecodeTable(src[i + 1]);
        if (input[1] == Hex!"ff")
            return null;

        output[outpos % 4] = ((input[0] << 2) | (input[1] >> 4)).to!char;
        if (++outpos % 4 == outstart) {
            auto result = utf16BufToUtf8(output, outstart);
            if (result is null) {
                return null;
            } else { ret.put(result); }
        }

        input[2] = lookup!Base64DecodeTable(src[i + 2]);
        if (input[2] == Hex!"ff") {
            if (src[i + 2] != '-')
                return null;
            i += 2;
            break;
        }
        output[outpos % 4] = ((input[1] << 4) | (input[2] >> 2)).to!char;
        if (++outpos % 4 == outstart) {
            auto result = utf16BufToUtf8(output, outstart);
            if (result is null) {
                return null;
            } else {
                ret.put(result);
            }
        }

        input[3] = lookup!Base64DecodeTable(src[i + 3]);
        if (input[3] == Hex!"ff") {
            if (src[i + 3] != '-')
                return null;
            i += 3;
            break;
        }

        output[outpos % 4] = (((input[2]) << 6) & Hex!"c0") | input[3];
        if (++outpos % 4 == outstart) {
            auto result = utf16BufToUtf8(output, outstart);
            if (result is null) {
                return null;
            } else {
                ret.put(result);
            }
        }
        i += 4;
    }
    if (outstart != outpos % 4) {
        auto len  = (4 + outpos - outstart) % 4;
        auto result = utf16BufToUtf8(output[0 .. len], outstart);
        if (result is null) {
            return null;
        } else { ret.put(result); }
    }
    return ret.data;
}

/// Convert a mailbox name from the modified UTF-7 encoding, according to RFC 3501 Section 5.1.3.
string utf7ToUtf8(string src) {
    import std.array : Appender;
    import std.algorithm : all, any;
    import std.string : indexOf;
    Appender!string ret;

    bool isValid = src.all!(c => c.isValidUtf7);
    if (!isValid)
        return null;

    auto j = src.indexOf('&');
    if (j == -1) // no encoded characters
        return src;

    if (j > 0) ret.put(src[0 .. j - 1]);

    size_t i = 0;
    while (i < src.length) {
        auto c = src[i];
        if (c != '&') {
            ret.put(src[i++]);
        } else {
            if (src[++i] == '-') {
                ret.put('&');
                ++i;
            } else {
                auto result = modifiedBase64DecodeToUtf8(src[i .. $]);
                if (result is null) {
                    return null;
                } else {
                    ret.put(result);
                }
                if (src[i] == '&' && src[i + 1] != '-')
                    return null;
            }
        }
    }
    return ret.data;
}
// at least one encoded character
private bool utf7IsValid(string src) {
    foreach (i, c; src) {
        if (c < Hex!"020" || c > Hex!"07f")
            return false;
        if (c == '&') {
            // slow scan
            auto ret = utf7ToUtf8(src[i .. $]);
            if (ret is null)
                return false;
        }
    }
    return true;
}


///
struct Mailbox {
    string mailbox;
    string prefix = "";
    char delim = '/';

    ///
    string toString() const {
        return applyNamespace();
    }

    /// Convert the names of personal mailboxes, using the namespace specified
    /// by the mail server, from internal to mail server format.
    string applyNamespace() const {
        import std.experimental.logger : infof;
        import std.string : toUpper, replace;
        import std.format : format;

        if (mailbox.toUpper != "INBOX")
            return mailbox;
        auto mbox = utf8ToUtf7(mailbox);
        if ((prefix.length == 0) && ((delim == '\0') || delim == '/'))
            return mbox;
        auto ret = format!"%s%s"(prefix, mbox).replace("/", [delim]);
        version(Trace) infof("namespace: '%s' -> '%s'\n", mbox, ret);
        return ret;
    }
    //// Convert the names of personal mailboxes, using the namespace specified by
    //// the mail server, from mail server format to internal format.
    static Mailbox fromServerFormat(string mbox, string prefix, char delim) {
        Mailbox ret = {
            mailbox : mbox.reverseNamespace(prefix, delim),
            prefix : prefix,
            delim : delim,
        };
        return ret;

    }
}

string reverseNamespace(string mbox, string prefix, char delim) {
    import std.string : toUpper, replace;
    int n;
    char *c;
    auto o = prefix.length;
    auto mboxU = mbox.toUpper;
    auto prefixU = prefix.toUpper;

    if (mboxU == "INBOX")
        return mbox;

    if ((o == 0 && delim == '\0')
        || (o == 0 && delim == '/'))
        return utf7ToUtf8(mbox);

    if (mbox.length >= prefix.length && mboxU[0 .. prefix.length] == prefixU)
        o = 0;

    return mbox[o .. $]
           .replace(delim, '/')
           .utf7ToUtf8;
}


alias unichar_t = int;
private int utf8GetChar(string src_) { // , char chr_r)
    import std.exception : enforce;
    import std.range : front;

    enum lowest_valid_chr_table = [0,
                                   0,
                                   to!int ("80", 16),
                                   to!int ("800", 16),
                                   to!int ("10000", 16),
                                   to!int ("200000", 16),
                                   to!int ("4000000", 16),
        ];

    string input = src_;
    unichar_t lowest_valid_chr;
    size_t i;
    int ret;
    enum max_len = cast(size_t) -1L;

    if (input.front < Hex!"80") {
        return input.front;
    }

    // first byte has len highest bits set, followed by zero bit.
    // the rest of the bits are used as the highest bits of the value

    unichar_t chr = input.front;
    size_t len = utf8CharBytes(chr);
    switch (len) {
        case 2:
            chr &= 0x1f;
            break;

        case 3:
            chr &= 0x0f;
            break;

        case 4:
            chr &= 0x07;
            break;

        case 5:
            chr &= 0x03;
            break;

        case 6:
            chr &= 0x01;
            break;

        default:
            // only 7bit chars should have len==1
            enforce(len == 1);
            return -1;
    }

    if (len <= max_len) {
        lowest_valid_chr = lowest_valid_chr_table[len];
        ret = 1;
    } else {
        // check first if the input is invalid before returning 0
        lowest_valid_chr = 0;
        ret = 0;
        len = max_len;
    }

    // the following bytes must all be 10xxxxxx
    for (i = 1; i < len; i++) {
        if ((input[i] & Hex!"c0") != Hex!"80")
            return (input[i] == '\0') ? 0 : -1;

        chr <<= 6;
        chr |= input[i] & Hex!"3f";
    }
    if (chr < lowest_valid_chr) {
        /* overlong encoding */
        return -1;
    }

    return chr;
}

/// Returns the number of bytes belonging to this UTF-8 character. The given
/// parameter is the first byte of the UTF-8 sequence. Invalid input is
/// returned with length 1
private uint utf8CharBytes(int chr) {
    /* 0x00 .. 0x7f are ASCII. 0x80 .. 0xC1 are invalid. */
    if (chr < (192 + 2))
        return 1;
    return utf8_non1_bytes[chr - (192 + 2)];
}

private const char[256 - 192 - 2] utf8_non1_bytes = [
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 1, 1
];


/+
    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
     to deal in the Software without restriction, including without limitation
     the rights to use, copy, modify, merge, publish, distribute, sublicense,
     and/or sell copies of the Software, and to permit persons to whom the
     Software is furnished to do so, subject to the following conditions:

     The above copyright notice and this permission notice shall be included in
     all copies or substantial portions of the Software.

     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
     IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
     FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
     AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
     LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
     FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
     DEALINGS IN THE SOFTWARE.

     utf7 code taken from Dovecot by Timo Sirainen <tss@iki.fi>
+/
