module imap.sildoc;

version (SILdoc) {
    import kaleidic.sil.lang.types : SILdoc;
} else {
    struct SILdoc {
        string value;
    }
}

