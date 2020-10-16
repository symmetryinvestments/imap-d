# SIL Examples

This directory contains some examples of how to use the **imap-d** SIL plugin.

## Biff

`biff.sil` implements a simple [Biff-like](https://en.wikipedia.org/wiki/Biff_(Unix)) utility.

```console
$ IMAP_USER=alice IMAP_PASS='secret' sil biff.sil -- --host=imap.example.com --port=993
   _____   ______   __
 //  ___\ ||_   _| || |
 \\ `--.    || |   || |
   `--. \   || |   || |
 //___/ /  _|| |_  || |___
 \\____/  ||_____| ||_____|
Symmetry Integration Language
Version: 2.4.0

- loading biff.sil
INBOX: 5 new, 6 total.
```

## List Mailboxes

`list_mailboxes.sil` shows the hierarchy of all the IMAP mailboxes.  Mailboxes
with sub-folders are marked with a '+'.

```console
$ IMAP_USER=alice IMAP_PASS='secret' sil list_mailboxes.sil -- --host=imap.example.com --port=993
   _____   ______   __
 //  ___\ ||_   _| || |
 \\ `--.    || |   || |
   `--. \   || |   || |
 //___/ /  _|| |_  || |___
 \\____/  ||_____| ||_____|
Symmetry Integration Language
Version: 2.4.0

- loading list_mailboxes.sil
Mailboxes:
  + archive
    archive.work
    archive.personal
    spam
    INBOX
```
## Headers

`headers.sil` provides a quick summary of the mail in a mailbox.  It prints the date, from and
subject fields in the order they appear in the mailbox.

```console
$ IMAP_USER=alice IMAP_PASS='secret' sil headers.sil -- --host=imap.example.com --port=993
   _____   ______   __
 //  ___\ ||_   _| || |
 \\ `--.    || |   || |
   `--. \   || |   || |
 //___/ /  _|| |_  || |___
 \\____/  ||_____| ||_____|
Symmetry Integration Language
Version: 2.4.0

- loading headers.sil
INBOX:
  Wed, 19 Jul 2017 14:28:21 +1000 (AEST)   | carlos <carlos@example.com>              | older email
  Tue, 24 Dec 2019 20:51:04 +1100 (AEDT)   | bob <bob@example.com>                    | test 1
  Fri, 31 Jan 2020 13:41:41 +1100 (AEDT)   | bob <bob@example.com>                    | recent email
```

## Search

`search.sil` searches for messages matching a pattern with optional formatted reporting.

An example support mailbox:
```
"support.mbox": 17 messages 17 new
 N  1 robot@example.com     Mon May 11 22:26  28/1369  "Alert: new issue 123"
 N  2 robot@example.com     Tue May 12 12:20  22/933   "Notification: service change"
 N  3 robot@example.com     Tue May 12 12:36  26/1341  "Alert: new issue 124"
 N  4 robot@example.com     Wed May 13 02:13  21/921   "Resolution: issue 124"
 N  5 person@example.com    Wed May 13 18:53  26/1332  "Email not from robot."
 N  6 robot@example.com     Thu May 14 03:13  27/1339  "Alert: new issue 125"
 N  7 robot@example.com     Thu May 14 08:46  26/1270  "Resolution: issue 123"
 N  8 robot@example.com     Thu May 14 17:06  25/1249  "Alert: new issue 126"
 N  9 robot@example.com     Fri May 15 09:46  24/1185  "Resolution: issue 126"
 N 10 robot@example.com     Fri May 15 12:33  23/1052  "Alert: new issue 127"
 N 11 robot@example.com     Fri May 15 15:20  27/1331  "Notification: service change"
 N 12 robot@example.com     Fri May 15 18:06  23/953   "Resolution: issue 127"
 N 13 robot@example.com     Mon May 18 12:46  27/1218  "Alert: new issue 128"
 N 14 robot@example.com     Mon May 18 15:33  32/1628  "Alert: new issue 129"
 N 15 robot@example.com     Tue May 19 05:26  25/1176  "Resolution: issue 128"
 N 16 robot@example.com     Tue May 19 08:13  26/1312  "Notification: service change"
 N 17 robot@example.com     Tue May 19 11:00  28/1275  "Alert: new issue 130"
```
Each of these automated emails are from `robot` _except_ for message 5.  Messages 2, 8 and 16 are
from `robot` but are unrelated to issues.

The script performs a search using the format specified in the [IMAP RFC](https://tools.ietf.org/html/rfc3501#section-6.4.4).

> E.g.,
> SEARCH FROM robot@example.com SUBJECT "Alert: new issue" SENTSINCE 13-may-2020

It will correlate the resolutions IDs with alert IDs and print a report showing the outstanding
issues.

```console
$ IMAP_USER=alice IMAP_PASS='secret' sil search.sil -- --host=imap.example.com --port=993
   _____   ______   __
 //  ___\ ||_   _| || |
 \\ `--.    || |   || |
   `--. \   || |   || |
 //___/ /  _|| |_  || |___
 \\____/  ||_____| ||_____|
Symmetry Integration Language
Version: 2.4.0

- loading search.sil

UNRESOLVED ISSUES FROM THE PAST 10 DAYS:

Issue: 125
  Date: Thu, 14 May 2020 03:13:20 +1000 (AEST)
  Summary: Process 123 'perl' crashed.
Issue: 129
  Date: Mon, 18 May 2020 15:33:20 +1000 (AEST)
  Summary: Unexpected reboot.
Issue: 130
  Date: Tue, 19 May 2020 11:00:00 +1000 (AEST)
  Summary: Snack box is empty.
```

For the example emails above it found that issues 125, 129 and 130 were unresolved and printed the
date they were reported and the first line from the message body for a summary.

This is a fairly contrived example but it shows how searching for specific criteria can be used to
generate a useful automated report.
