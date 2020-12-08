///
module imap.namespace;

immutable B64Enc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+,";
immutable ubyte[256] B64Dec = [
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0x3e, 0x3f,0xff,0xff,0xff,
    0x34,0x35,0x36,0x37, 0x38,0x39,0x3a,0x3b, 0x3c,0x3d,0xff,0xff, 0xff,0xff,0xff,0xff,
    0xff,0x00,0x01,0x02, 0x03,0x04,0x05,0x06, 0x07,0x08,0x09,0x0a, 0x0b,0x0c,0x0d,0x0e,
    0x0f,0x10,0x11,0x12, 0x13,0x14,0x15,0x16, 0x17,0x18,0x19,0xff, 0xff,0xff,0xff,0xff,
    0xff,0x1a,0x1b,0x1c, 0x1d,0x1e,0x1f,0x20, 0x21,0x22,0x23,0x24, 0x25,0x26,0x27,0x28,
    0x29,0x2a,0x2b,0x2c, 0x2d,0x2e,0x2f,0x30, 0x31,0x32,0x33,0xff, 0xff,0xff,0xff,0xff,
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
    0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff, 0xff,0xff,0xff,0xff,
];

string utf8ToUtf7(string utf8Src) {
    import std.conv : to;
    import std.array : Appender;

    Appender!string utf7Dst;

    bool inAsciiMode = true;

    // As we encode base64 we'll have potentially 0, 2 or 4 bits remaining to be encoded at any one
    // time.  remBits keeps them in its LSBs.
    uint remBits = 0;
    uint numRemBits = 0;

    foreach (wch; utf8Src.to!wstring) {
        // If input is ASCII then switch to ASCII mode if necessary first.
        if (!inAsciiMode && wch < 0x7f) {
            if (numRemBits > 0) {
                utf7Dst.put(B64Enc[remBits << (6 - numRemBits)]);
            }
            utf7Dst.put('-');
            remBits = numRemBits = 0;
            inAsciiMode = true;
        }

        // Special case the '&'.
        if (wch == '&') {
            utf7Dst.put("&-");
            continue;
        }

        // If input is ASCII then just copy it.
        if (0x20 <= wch && wch <= 0x7e) {
            utf7Dst.put(wch.to!char);
            continue;
        }

        // Input is not ASCII.  Switch to BASE64 mode if necessary.
        if (inAsciiMode) {
            utf7Dst.put('&');
            inAsciiMode = false;
        }

        // Add our new character to the remaining bits.
        remBits = (remBits << 16) | wch.to!uint;
        numRemBits += 16;

        // Output base64 encoded chars while there are enough bits.
        while (numRemBits >= 6) {
            numRemBits -= 6;
            utf7Dst.put(B64Enc[remBits >> numRemBits]);
            remBits &= ((1 << numRemBits) - 1);
        }
    }
    if (!inAsciiMode) {
        if (numRemBits > 0) {
            utf7Dst.put(B64Enc[remBits << (6 - numRemBits)]);
        }
        utf7Dst.put('-');
    }

    return utf7Dst.data.to!string;
}

unittest {
    void encodeTest(string input, string expected) {
        import std.stdio : writeln;
        string got = utf8ToUtf7(input);
        if (got != expected) {
            writeln("INPUT:     ", input);
            writeln("EXPECTING: ", expected);
            writeln("GOT:       ", got);
        }
        assert(utf8ToUtf7(input) == expected);
    }

    // From RFC 2152.
    encodeTest("A≢Α.", "A&ImIDkQ-.");
    encodeTest("Hi Mom -☺-!", "Hi Mom -&Jjo--!");
    encodeTest("日本語", "&ZeVnLIqe-");

    // Stolen shamelessly from the Factor runtime tests.
    // https://github.com/factor/factor/blob/master/basis/io/encodings/utf7/utf7-tests.factor
    encodeTest("~/bågø", "~/b&AOU-g&APg-");
    encodeTest("båx", "b&AOU-x");
    encodeTest("bøx", "b&APg-x");
    encodeTest("test", "test");
    encodeTest("Skräppost", "Skr&AOQ-ppost");
    encodeTest("Ting & Såger", "Ting &- S&AOU-ger");
    encodeTest("~/Følder/mailbåx & stuff + more", "~/F&APg-lder/mailb&AOU-x &- stuff + more");
    encodeTest("~peter/mail/日本語/台北", "~peter/mail/&ZeVnLIqe-/&U,BTFw-");
}


string utf7ToUtf8(string utf7Src) {
    import std.array : Appender;
    import std.conv : to;

    Appender!wstring unicodeDst;

    bool inAsciiMode = true;
    bool prevWasAmp = false;    // A bit of a hack to handle the '&-' special case.

    // As we decode base64 we'll buffer up bits until we have enough to output a unicode character.
    uint bufBits = 0;
    uint numBufBits = 0;

    foreach (ch; utf7Src) {
        // Copy ASCII characters directly.
        if (inAsciiMode && ch >= 0x20 && ch <= 0x7e) {
            if (ch != '&') {
                unicodeDst.put(ch);
            } else {
                inAsciiMode = false;
                prevWasAmp = true;
            }
            continue;
        }

        // It's an escaped code.  Is it the end marker?
        bool newAmp = prevWasAmp;
        prevWasAmp = false;
        if (ch == '-') {
            if (newAmp) {
                // Special case for '&-'.  Hacky. :(
                unicodeDst.put('&');
            }
            bufBits = numBufBits = 0;
            inAsciiMode = true;
            continue;
        }

        // Decode UTF-7 character.
        bufBits = (bufBits << 6) | B64Dec[ch];
        numBufBits += 6;

        if (numBufBits >= 16) {
            numBufBits -= 16;
            unicodeDst.put(((bufBits >> numBufBits) & 0xffff).to!wchar);
            bufBits &= ((1 << numBufBits) - 1);
        }
    }

    return unicodeDst.data.to!string;
}

unittest {
    void decodeTest(string input) {
        import std.stdio : writeln;
        import std.conv : to;
        string utf7 = utf8ToUtf7(input);
        string got = utf7ToUtf8(utf7);
        if (got != input) {
            writeln("INPUT: ", input);
            writeln("UTF-7: ", utf7);
            writeln("GOT:   ", got);
        }
        assert(utf7ToUtf8(utf8ToUtf7(input)) == input);
    }

    // From RFC 2152.
    decodeTest("A≢Α.");
    decodeTest("Hi Mom -☺-!");
    decodeTest("日本語");

    // Stolen shamelessly from the Factor runtime tests.
    // https://github.com/factor/factor/blob/master/basis/io/encodings/utf7/utf7-tests.factor
    decodeTest("~/bågø");
    decodeTest("båx");
    decodeTest("bøx");
    decodeTest("test");
    decodeTest("Skräppost");
    decodeTest("Ting & Såger");
    decodeTest("~/Følder/mailbåx & stuff + more");
    decodeTest("~peter/mail/日本語/台北");
}

