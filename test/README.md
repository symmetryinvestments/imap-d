# `imap-d` Functional Testing

This D project is a simple binary which tests the `imap-d` library.  It requires a running IMAP
server which may be built using LXC containers and [packer](https://packer.io).

## Set up.

First time set up requires the IMAP container image to be built.

```bash
packer build alpine-dovecot.json
```

This will build a new Linux container image called `dovecot-test`, based on [Alpine Linux](https://alpinelinux.org) with an
instance of [Dovecot](https://www.dovecot.org) installed and running.

## Running.

The tests themselves can be built with `dub` which will produce a single binary called `imap-d-test`.

```bash
dub build
```

The Dovecot container must be running and either have a bridged network interface which may be
visible from the host or a NAT'd interface which will be visible from other LXD containers.

```console
$ lxc launch dovecot-test
Creating the instance
Instance name is: dovecot-test
Starting dovecot-test

$ lxc list
+---------------+---------+-----------------------+--------------- ... -+-----------+-----------+
| NAME          | STATE   | IPV4                  | IPV6           ...  | TYPE      | SNAPSHOTS |
+---------------+---------+-----------------------+--------------- ... -+-----------+-----------+
| dovecot-test  | RUNNING | 10.252.193.187 (eth0) | fd42:cbf9:2f5: ...  | CONTAINER | 0         |
+---------------+---------+-----------------------+--------------- ... -+-----------+-----------+
```

Then the tests can be started by passing the container IP to the test binary.  Depending on your
setup with might be by name, e.g., `dovecot-test.lxd` or by number.

```console
./test-imap-d 10.252.193.187
auth      - passed.
mailbox   - passed.
subscribe - passed.
append    - passed.
status    - passed.
select    - passed.
copy      - passed.
store     - passed.
examine   - passed.
close     - passed.
fetch     - passed.
search    - passed.
uid       - passed.
```

## Adding tests.

The tests are run in order and try to introduce new APIs before they are needed by other tests.
They assume that the IMAP user mailbox is completely empty at the start of testing and each test
leaves the user mailbox empty on success.

If any tests fail then the test run aborts as subsequent tests may rely on functionality from prior
tests which is assumed to be working.  This may also leave the mailbox in a non-empty state.  This
can be quickly remedied by removing the user mailbox externally before updating the tests and trying
again.

```bash
lxc exec dovecot-test -- rm -r /home/mailuser/Maildir
```

