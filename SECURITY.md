# Security

This document describes the security model of this project: what is isolated, what is forwarded, and what the residual attack surface is.

---

## Docker-in-Docker with TLS

### Architecture

The project uses a `docker:dind` sidecar container (`daemon` service) instead of mounting the host's `/var/run/docker.sock`. This is a deliberate security boundary.

```
Host machine
├── /var/run/docker.sock    ← never mounted into any container
└── Docker
    ├── workstation
    │   └── DOCKER_HOST=tcp://daemon:2376  (TLS)
    └── daemon (docker:dind)
        └── /var/lib/docker  (named volume, isolated from host)
```

### Why this matters

Mounting the host Docker socket into a container grants that container root-equivalent access to the host machine. Any process inside the container — including a compromised npm package, a rogue dependency, or a supply-chain attack — could use it to escape the container entirely.

With the DinD sidecar, a compromised process inside a devcontainer can only reach the isolated daemon. It sees its own images and volumes, not the host's.

### TLS configuration

Communication between the workstation and the daemon uses mutual TLS (`tcp://daemon:2376`). The daemon generates certificates automatically on first startup via `DOCKER_TLS_CERTDIR=/certs`. The certificates are stored in a named volume (`certs-client`) shared between the two services and are never written to the host filesystem.

Relevant environment variables:
- `DOCKER_HOST=tcp://daemon:2376`
- `DOCKER_TLS_VERIFY=1`
- `DOCKER_CERT_PATH=/certs/client`

The `certs-client` volume is mounted read-only (`:ro`) in the workstation.

---

## SSH agent forwarding

### How it works

Private repositories are cloned using the host SSH agent via a socket bind mount:

```yaml
volumes:
  - ${SSH_AUTH_SOCK}:/tmp/ssh-agent.sock
environment:
  - SSH_AUTH_SOCK=/tmp/ssh-agent.sock
```

The SSH agent protocol proxies signing operations back to the host agent. **Private keys never leave the host machine** — they are never copied into any container filesystem.

### What this grants

Any process inside the workstation container that can reach `/tmp/ssh-agent.sock` can ask the host agent to sign data (i.e., authenticate to SSH servers). This is the standard trade-off of SSH agent forwarding.

The workstation container is treated as trusted (it is the management layer, not the untrusted project code). The devcontainers do not receive the SSH agent socket.

### Residual risk

- If the workstation container is compromised, an attacker could use the forwarded agent to authenticate to any server your SSH key has access to, for the duration of the session.
- This risk exists in any SSH agent forwarding setup. Mitigations: use a time-limited key (`ssh-add -t 3600`), revoke keys after the session, use separate keys for this workstation.

### Verification

```bash
# On host: confirm keys are loaded
ssh-add -l

# Inside workstation: confirm forwarding works
ssh-add -l
```

Both should list the same keys.

---

## Attack surface summary

| Surface | Isolation | Notes |
|---|---|---|
| Host Docker socket | Fully isolated | Never mounted; DinD sidecar used instead |
| Host filesystem | Partially exposed | `workspace/`, `scripts/`, `templates/` are bind-mounted; `.env` is not |
| SSH private keys | Not exposed | Agent forwarding only; keys stay on host |
| TLS certificates | Isolated | Named volume, not on host filesystem; mounted `:ro` in workstation |
| Bash history | Isolated | Named volume, not accessible outside Docker |
| `ANTHROPIC_API_KEY` | In container env | Passed via environment variable from `.env`; not written to disk inside container |

---

## Reporting a vulnerability

If you discover a security issue, please do not open a public GitHub issue. Instead, email the maintainer directly or use GitHub's private vulnerability reporting feature (Security > Report a vulnerability).

Please include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (optional)

You will receive a response within 5 business days.
