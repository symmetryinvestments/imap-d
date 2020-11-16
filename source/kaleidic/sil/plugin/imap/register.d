///
module kaleidic.sil.plugin.imap.register;

import imap.set;
import std.meta : AliasSeq;

version (SIL) : import kaleidic.sil.lang.handlers : Handlers;

import kaleidic.sil.lang.typing.types : Variable, Function, SILdoc;

version (SIL_Plugin) {
    import kaleidic.sil.lang.plugin : pluginImpl;
    mixin pluginImpl!registerImap;
}

import imap.defines;
import imap.socket;
import imap.session : Session;

import std.socket;

import arsd.email : MimeContainer;

///
void registerImap(ref Handlers handlers) {
    import imap.session;
    import imap.request;
    import imap.response;
    import imap.namespace;
    import deimos.openssl.ssl;
    import deimos.openssl.evp;
    import arsd.email : IncomingEmailMessage, RelayInfo, ToType, EmailMessage, MimePart;

    {
        handlers.openModule("imap");
        scope (exit) handlers.closeModule();

        static foreach (T; AliasSeq!(MailboxList, Mailbox, ImapResult, ImapStatus, Result!string,
                                     Status, FlagResult, SearchResult, Session, ProtocolSSL,
                                     ImapServer, ImapLogin, StatusResult, BodyResponse,
                                     ListResponse, ListEntry, IncomingEmailMessage, RelayInfo,
                                     ToType, EmailMessage, MimePart, Options, MimeContainer_,
                                     MimeAttachment, SearchResultType,
                                     StoreMode // proxy from imap not arsd
                                    )) {
            handlers.registerType!T;
        }

        handlers.registerType!(Set!Capability)("Capabilities");

        handlers.registerType!(Set!ulong)("UidSet");
        handlers.registerHandler!(addSet!ulong)("addUidSet");
        handlers.registerHandler!(removeSet!ulong)("removeUidSet");

        // FIXME - finish and add append
        static foreach (F; AliasSeq!(noop, login, logout, status, examine, select, close, expunge,
                                     list, lsub, search, fetchFast, fetchFlags, fetchDate,
                                     fetchSize, fetchStructure, fetchHeader, fetchText, fetchFields,
                                     fetchPart, store, copy, create, delete_, rename, subscribe,
                                     unsubscribe, idle, openConnection, closeConnection,
                                     fetchRFC822, attachments, writeBinaryString, esearch,
                                     multiSearch, move, multiMove, moveUIDs,
                        )) {
            handlers.registerHandler!F;
        }
        handlers.registerType!Socket;

        import jmap : registerHandlersJmap;
        handlers.registerHandlersJmap();
    }

    {
        handlers.openModule("ssl");
        scope (exit) handlers.closeModule();
        static foreach (T; AliasSeq!(EVP_MD, SSL_))
            handlers.registerType!T;
        handlers.registerType!X509_("X509");
    }
}

void writeBinaryString(string file, string data) {
    import std.file;
    write(file, data);
}

struct X509_ {
    import deimos.openssl.x509;
    X509* handle;
}

struct MimeContainer_ {
    MimeContainer h;
    string contentType() { return h._contentType; }
    string boundary() { return h.boundary; }
    string[] headers() { return h.headers; }
    string content() { return h.content; }

    MimeContainer_[] stuff() {
        import std.algorithm : map;
        import std.array : array;
        return h.stuff.map!(s => MimeContainer_(s)).array;
    }

    this(MimeContainer h) {
        this.h = h;
    }
}

MimeContainer_ accessMimeContainer(MimeContainer mimeContainer) {
    return MimeContainer_(mimeContainer);
}

