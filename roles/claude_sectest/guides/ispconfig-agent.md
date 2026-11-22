# ISPConfig Agent Knowledge

Operational knowledge for agents working with an ISPConfig-managed mail server.
These are known behaviors, expected quirks, and context needed to interpret
monitoring output correctly.

---

## postfix check warnings

### TLS key/cert not owned by root

```
postfix/postfix-script: warning: not owned by root: /etc/postfix/./smtpd.key
postfix/postfix-script: warning: not owned by root: /etc/postfix/./smtpd.cert
```

**This is normal on ISPConfig hosts.** ISPConfig's cert management sets ownership
to `postfix:postfix 0600` rather than `root:root`. The security posture is
equivalent — the key is unreadable by any other user. `postfix check` exits 0
despite the warnings. Do not flag this as an issue.

---

## Sieve

ISPConfig uses Dovecot's Pigeonhole sieve implementation. On Debian 12:

- Plugin modules: `/usr/lib/dovecot/modules/sieve/`
- Per-user script: `~/.sieve`
- ISPConfig spam filter: `~/.ispconfig.sieve` (applied after user script)
- ISPConfig pre-filter: `~/.ispconfig-before.sieve` (applied before user script)

The `sieve_after` / `sieve_before` hooks are ISPConfig's spam/filter pipeline.
If a user's mail is being sorted unexpectedly, check `.ispconfig.sieve` first.

---

## Dovecot auth failures

High auth failure counts in `journalctl -u dovecot` are **expected and normal**
on a public-facing VPS. Credential stuffing against IMAP is constant background
noise. 200–500 failures per 24h is unremarkable. Fail2ban handles banning.

Look for spikes (10x normal rate) or failures from known-good client IPs as
signals worth investigating.

---

## Mail queue

Postfix on ISPConfig uses virtual domains backed by MySQL. Queue IDs are
alphanumeric (6–20 chars). The `mail-agent-op` wrapper exposes:

- `envelope <qid>` — inspect headers and envelope without releasing
- `hold <qid>` / `release <qid>` — quarantine or release a specific message
- `requeue <qid>` — force immediate retry of a deferred message

The special queue ID `ALL` is blocked by the wrapper's `qid()` validator
(minimum 6 chars also blocks it).

---

## Postfix recipient restrictions (ISPConfig standard)

The ISPConfig-managed `smtpd_recipient_restrictions` is long by design:

```
permit_mynetworks,
reject_unknown_recipient_domain,
reject_unlisted_recipient,
permit_sasl_authenticated,
reject_non_fqdn_recipient,
reject_unauth_destination,
check_recipient_access proxy:mysql:/etc/postfix/mysql-virtual_recipient.cf,
check_recipient_access mysql:/etc/postfix/mysql-virtual_policy_greylist.cf,
check_policy_service unix:private/quota-status
```

This chain validates domain existence, SASL auth, FQDN, relay permission,
per-recipient access policy (MySQL-backed), greylisting, and quota enforcement
in order. `NOQUEUE: reject` in the postfix journal is this chain working correctly.

---

## smtpd_tls_security_level = may

ISPConfig sets TLS to `may` (opportunistic) rather than `encrypt` (required).
This is intentional — enforcing TLS breaks compatibility with legacy senders.
Do not recommend changing this to `encrypt` without understanding the tradeoff.

---

## doveadm log errors

Run via `sudo doveadm log errors`. On a healthy server this is often empty or
shows only transient auth-worker restarts. Persistent errors here (quota backend
failures, MySQL connection issues) are worth escalating.
