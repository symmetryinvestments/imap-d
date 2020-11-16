module imap.sil;

version (SIL) {
    public import kaleidic.sil.lang.typing.types : SILdoc;
} else {
    struct SILdoc {
        string value;
    }
}

