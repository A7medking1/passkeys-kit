# Security policy

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately through GitHub instead: open the repository's **Security** tab and choose **Report a vulnerability**.

Please include:

- what an attacker could do, and under which conditions;
- the steps to reproduce it, ideally as a failing test with [`VirtualPasskey`](server/tests/virtual-authenticator.ts);
- the version or commit you tested.

You'll get a reply as soon as possible. Please give us time to fix the problem before you disclose it.

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |

## How the kit approaches security

[docs/security.md](docs/security.md) lists every check a passkey goes through, the choices behind them, and a checklist for apps that use the kit.
