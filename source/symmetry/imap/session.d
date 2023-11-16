///
module symmetry.imap.session;
import symmetry.imap.defines;
import symmetry.imap.socket;
import symmetry.imap.set;
import symmetry.imap.sil : SILdoc;

import core.stdc.stdio;
import core.stdc.string;
import core.stdc.errno;
import std.socket;
import core.time : Duration;

import deimos.openssl.ssl;
import deimos.openssl.err;
import deimos.openssl.sha;


struct SSL_ {
    SSL* handle;
    alias handle this;
}


///
Set!T removeValues(T)(Set!T set, T[] values) {
    import std.algorithm : each;
    Set!T ret;
    set.values_.byKeyValue.each!(entry => ret[entry.key] = entry.value);
    foreach (value; values) {
        if (value in ret)
            ret.remove(value);
    }
    return ret;
}

///
Set!T addValues(T)(Set!T set, T[] values) {
    import std.algorithm : each;
    Set!T ret;
    set.values_.byKeyValue.each!(entry => ret[entry.key] = entry.value);
    values.each!(value => set.values_[value] = true);
    return ret;
}

///
Set!T addSet(T)(Set!T lhs, Set!T rhs) {
    Set!T ret;
    return lhs.addValues(rhs.values);
}

///
Set!T removeSet(T)(Set!T lhs, Set!T rhs) {
    Set!T ret;
    return lhs.removeValues(rhs.values);
}

///
struct ImapServer {
    string server = "imap.fastmail.com"; // localhost";
    string port = "993";

    string toString() const {
        import std.format : format;
        return format!"%s:%s"(server, port);
    }
}

///
struct ImapLogin {
    @SILdoc("User's name. It takes a string as a value.")
    string username = "laeeth@kaleidic.io";

    @SILdoc("User's secret keyword. If a password wasn't supplied the user will be asked to enter one interactively the first time it will be needed. It takes a string as a value.")
    string password;

    @SILdoc("OAuth2 token, if present, it will try this before the username and password.")
    string oauthToken;

    string toString() const {
        import std.format : format;
        return format!"%s:[hidden]"(username);
    }
}

///
struct Options {
    import core.time : Duration, seconds, minutes;

    bool debugMode = false;
    bool verboseOutput = false;
    bool interactive = false;
    bool namespace = false;

    @SILdoc("When this option is enabled and the server supports the Challenge-Response Authentication Mechanism (specifically CRAM-MD5), this method will be used for user authentication instead of a plaintext password LOGIN. This variable takes a boolean as a value. Default is false")
    bool cramMD5 = false;

    bool startTLS = false;
    bool tryCreate = false;
    bool recoverAll = true;
    bool recoverErrors = true;

    @SILdoc("Normally, messages are marked for deletion and are actually deleted when the mailbox is closed. When this option is enabled, messages are expunged immediately after being marked deleted. This variable takes a boolean as a value. Default is false")
    bool expunge = false;

    @SILdoc("By enabling this option new mailboxes that were automatically created, get also subscribed; they are set active in order for IMAP clients to recognize them. This variable takes a boolean as a value. Default is false")
    bool subscribe = false;

    bool wakeOnAny = true;

    @SILdoc("The time in minutes before terminating and re-issuing the IDLE command, in order to keep alive the connection, by resetting the inactivity timeout of the server. A standards compliant server must have an inactivity timeout of at least 30 minutes. But it may happen that some IMAP servers don't respect that, or some intermediary network device has a shorter timeout. By setting this option the above problem can be worked around. This variable takes a number as a value. Default is 29 minutes. ")
    Duration keepAlive = 29.minutes;

    string logFile;
    string configFile;
    string oneline;
    Duration timeout = 20.seconds;
}

///
final class Mailbox {
    this(Session session, string mailbox) {
        this(session, [mailbox]);
    }
    this(Session session, Mailbox base, string mailbox) {
        this(session, base.path ~ mailbox);
    }
    this(Session session, string[] mailboxes) {
        if (session.namespaceDelim == '\0') {
            import std.exception : enforce;
            import symmetry.imap.request : list;

            // Fetch the delimiter *once* for the session.  We're assuming that INBOX exists, so
            // there will be at least one entry returned for us to inspect.
            auto resp = session.list();
            enforce(resp.status == ImapStatus.ok, "Failed to get listing in Mailbox().");
            session.namespaceDelim = resp.entries[0].hierarchyDelimiter[0];
        }
        path = mailboxes;
        delim = session.namespaceDelim;
    }

    ///
    override string toString() {
        import std.array : join;
        import std.string : toUpper, replace;
        import std.format : format;
        import symmetry.imap.namespace;

        if (utf7Path is null) {
            // XXX Or to we convert to utf-7 before joining?
            utf7Path = utf8ToUtf7(path.join(delim));
        }
        return utf7Path;
    }

    private {
        string[] path;
        char delim;
        string utf7Path;
    }
}

///
final class Session {
    import symmetry.imap.defines : ImapStatus;
    import symmetry.imap.namespace;
    Options options;
    ImapStatus status_;
    string server;

    @SILdoc("The port to connect to. It takes a number as a value. Default is ''143'' for imap and ''993'' for imaps.")
    string port;

    package AddressInfo addressInfo;
    ImapLogin imapLogin;
    Socket socket;
    ImapProtocol imapProtocol;
    Set!Capability capabilities;
    string namespacePrefix;
    char namespaceDelim = '\0';   // Use Nullable?
    Mailbox selected;

    bool useSSL = true;
    bool noCerts = true;
    ProtocolSSL sslProtocol = ProtocolSSL.tls1_2; // ssl3; // tls1_2;
    SSL* sslConnection;
    SSL_CTX* sslContext;

    override string toString() const {
        import std.array : Appender;
        import std.format : formattedWrite;
        Appender!string ret;
        ret.formattedWrite!"Session to %s:%s as user %s\n"(server, port, imapLogin.username);
        ret.formattedWrite!"- useSSL: %s\n"(useSSL);
        ret.formattedWrite!"- startTLS: %s\n"(options.startTLS);
        ret.formattedWrite!"- noCerts: %s\n"(noCerts);
        ret.formattedWrite!"- sslProtocol: %s\n"(sslProtocol);
        ret.formattedWrite!"- imap protocol: %s\n"(imapProtocol);
        ret.formattedWrite!" - capabilities: %s\n"(capabilities);
        ret.formattedWrite!" - namespace: %s/%s\n"(namespacePrefix, [namespaceDelim]);
        ret.formattedWrite!" - selected mailbox: %s\n"(selected);
        return ret.data;
    }

    this(ImapServer imapServer, ImapLogin imapLogin, bool useSSL = true, Options options = Options.init) {
        import std.exception : enforce;
        import std.process : environment;
        this.options = options;
        this.server = imapServer.server;
        this.port = imapServer.port;
        this.useSSL = useSSL;
        this.imapLogin = imapLogin;
    }

    Session useStartTLS(bool useTLS = true) {
        this.options.startTLS = useTLS;
        return this;
    }

    Session setSelected(Mailbox mailbox) {
        this.selected = mailbox;
        return this;
    }

    Session setStatus(ImapStatus status) {
        this.status_ = status;
        return this;
    }

    string status() {
        import std.conv : to;
        return status_.to!string;
    }
}

