# Cloud <-> Mac transport decision

Status: decided 2026-09-12. Decision only. Nothing on the machine, the router, or the
tailnet was changed by this document.

## Decision

**Primary: Tailscale Funnel carrying a WebSocket (WSS) control session, treated as an
internet-facing endpoint.** The Mac's native tailscaled keeps the only outbound
connection; the daemon listens on loopback; the cloud agent is a plain TLS client
holding a bearer token. No tailnet enrollment on the cloud side.

**Fallback: ssh over the DERP-relayed tailnet through the existing socks5 ControlMaster
(works today).** Used when the funnel path is down or when a verb needs a shell
rather than the whitelisted daemon.

**Offline path (Mac asleep or roaming): the planned vault-folder queue.** The daemon
drains it on wake and on every socket establish, deduplicated by command id.

Named escalation, not chosen now: if Funnel proves flaky or bandwidth-capped, replace
it with a self-run rendezvous (100-line relay on a VPS, or Cloudflare Tunnel). Same
shape, different owner. Nothing in the daemon changes except the hostname.

## The one fact that decides it

Both ends are egress-only. The cloud sandbox has no UDP, no IPv4 endpoint, no IPv6,
and cannot accept inbound. The Mac sits behind a router with no UPnP/NAT-PMP/PCP.
Two egress-only hosts cannot reach each other without a third box that both dial.
**A relay is not a band-aid; it is the topology.** The real choice is whose relay,
what protocol rides it, and which side carries the enrollment cost.

The band-aid in the current setup is not the relay. It is enrolling an ephemeral
cloud sandbox as a tailnet node so that a WireGuard tunnel can be forced over TCP to
reach a daemon that already guards itself with a token. That pays the tailnet's costs
(auth key in the sandbox, userspace netstack, per-session node churn, ACL trust) and
gets none of its value (direct WireGuard is impossible from that side).

## Latency math

Measured 2026-09-12: cloud->DERP ord 49.4 ms, Mac->DERP ord 35.7 ms, cloud<->Mac
tailscale ping 108-226 ms through the relay. Any relay placed near ord gives the same
one-way path of roughly 85 ms, so RTT is ~170 ms for every relayed option. Physics,
not vendor, sets this floor. Latency does not discriminate between options; it only
confirms all of them fit the budget on a warm connection.

| Path | Round trips | Wire time | Local execution | Total |
|---|---|---|---|---|
| Device verb (raise, open-url, display) | 1 | ~0.2 s | 0.1-0.5 s | 0.3-0.7 s |
| Click-and-verify (click, then screenshot back) | 2 | ~0.4 s | 0.2-0.5 s + 100-300 KB upload | 0.7-1.5 s |
| Cold dial (TLS + WSS upgrade) before first verb | 3 | ~0.5 s | - | adds 0.5 s once |

The <1 s device budget and 1-2 s click-and-verify budget hold only on a **warm**
socket. A per-request HTTPS call (today's curl to cmd-server) spends 2-3 RTTs on TLS
setup each time and lands at 0.6-0.9 s before execution. That is why the control
session must be a held WSS, not request-per-verb HTTP.

## Options

### (a) DERP-relayed tailnet as-is: rejected as primary, kept as fallback

- Latency: fine (~170 ms RTT), same floor as everything else.
- Security: WireGuard plus tailnet ACLs. Sounds strong, but the auth key must live in
  each cloud sandbox, so tailnet membership becomes a per-session secret with a
  blast radius of the whole tailnet, not one daemon.
- Reliability: native tailscaled on the Mac roams and wakes well. The cloud side runs
  userspace tailscaled inside a sandbox that is torn down per session, so every
  session re-enrolls and re-learns the relay path.
- Simplicity: worst of the set. Two tailscaled processes, a socks5 proxy, ControlMaster,
  and a keepalive loop, all to deliver small JSON to a token-guarded loopback daemon.
- Verdict: the ssh path is proven and stays as fallback. It does not become the
  control socket.

### (b) Mac-dialed persistent WSS to a cloud public endpoint: impossible as stated

The cloud agent has no public endpoint. The sandbox cannot listen. "Cloud public
endpoint" therefore means a third box we run (VPS, Fly, Cloudflare Worker with a
Durable Object). That is a self-run rendezvous: same physics, same ~170 ms, and it
adds a host to keep alive, a relay to write, a certificate to renew, and a second
secret. It gains exactly one thing over Funnel: not depending on Tailscale. That is
not worth a new always-on component today. Kept as the named escalation because the
daemon design below is identical for it.

### (c) Direct IPv6 to the Mac: rejected on evidence

The cloud side has no IPv6. There is no v6 packet to send, so the router pinhole
question never arises. Even if the sandbox gained v6 later: the Mac's global address
changes on every roam (new prefix away from home, privacy extensions at home), so the
cloud would need a discovery channel anyway, and the Mac would hold an internet-facing
listener on its own interface. Not revisited unless the cloud gains v6 egress.

### (d) Tailscale Funnel as the transport: chosen

- Latency: cloud -> Funnel ingress (Tailscale's relay near ord) -> Mac's existing
  DERP connection. Same ~170 ms floor. TLS terminates on the Mac, so the relay sees
  ciphertext only.
- Security: Funnel is public by definition, so rule (1) applies with no argument.
  Token plus TLS do all the guarding; no ACL assumption exists to be wrong. The
  cloud side holds one narrow secret (the daemon token), not tailnet membership.
- Reliability: only the Mac's native tailscaled holds an outbound connection, and it
  already survives sleep/wake and Wi-Fi roaming (verified daily by the current ssh
  path). The public hostname never changes, so the cloud needs no discovery.
- Simplicity: Funnel already runs on this Mac (8443, TLS-terminated TCP to
  localhost:22 for the ssh fallback; checked 2026-09-12 with `tailscale serve
  status`). cmd-server is currently exposed tailnet-only on 8444. Going live means
  adding one funnel entry for the daemon on a second port, or moving ssh off 8443.
  The cloud side is `curl` or any WebSocket client; no tailscaled, no proxy, no
  ControlMaster.
- Cost: the Mac's daemon is reachable from the internet, gated only by the token.
  That is the same posture cmd-server already runs under, now stated as design
  rather than accident. Mitigations are in "Security posture" below.

### (e) Hybrid: this is a hybrid

Funnel WSS for live control, ssh-over-DERP for shell and as fallback, vault queue
for offline. Three paths, one daemon, one token model. What this decision refuses is
a hybrid at the packet level (racing DERP against a second relay), which doubles the
moving parts for no latency gain.

## Security posture under rule (1)

Design the endpoint as internet-facing, because it is.

1. **Token in a header or the first WSS frame, never in the URL path.** cmd-server's
   current `/<token>/<verb>` puts the secret into every proxy and access log on the
   path. Change before the WSS goes live.
2. **One token per client role, rotatable without restart.** The daemon rereads
   `~/.perch-bridge/*.token` on SIGHUP. Compromise of the cloud sandbox costs one
   token, not the tailnet.
3. **Constant-time compare, 404 on failure, and a per-source rate limit** (10 failed
   auths per minute, then a 60 s silence) so the public port cannot be brute-forced
   or used to fingerprint the daemon.
4. **Whitelisted verbs stay whitelisted.** The `run` verb (arbitrary shell, his call
   2026-09-12) is the largest surface on a public endpoint. It requires a second,
   separate token from the device verbs, so a leaked device token cannot run shell.
5. **TLS is Tailscale-issued for the funnel hostname and terminates on the Mac.**
   The relay never sees plaintext. The cloud client pins nothing extra; the public
   CA chain is the guard, same as any HTTPS API.
6. **No inbound listener on any Mac interface.** The daemon binds 127.0.0.1 only.
   Funnel is the sole ingress and can be switched off with one command.

## Socket lifecycle

The Mac never dials the cloud. Its outbound connection is tailscaled's, already
maintained. The **cloud agent** owns the warm socket; the **daemon** owns wake and
queue behaviour.

### Cloud client (one WSS per session, both lanes multiplexed)

- **Dial**: `wss://<funnel-host>:<daemon-port>/v1/ctl`, `Authorization: Bearer <token>`,
  connect timeout 5 s. First frame after upgrade: `{"hello": <session-id>, "since": <last-ack-id>}`.
- **Multiplex**: each frame carries `{"id", "lane": "device"|"orch", "verb", "args"}`.
  Device frames are answered in order of arrival; orch frames may stream partial
  output. The daemon never blocks a device frame behind an orch frame (two worker
  queues behind one socket).
- **Liveness**: client ping every 20 s; two missed pongs (40 s) close the socket.
  Replaces the 90 s keepalive loop, which is too slow to notice a sleep.
- **Reconnect backoff**: 1, 2, 4, 8, 16, 30 s cap, full jitter, forever. Every
  failed dial marks the Mac "away".
- **When away**: device verbs are written to the vault queue as
  `<queue>/<ISO-timestamp>-<id>.json` and the caller is told "queued". Orch verbs
  fall back to the ssh path if it is up, otherwise queue.
- **On establish**: send `since`; the daemon replies with acks for anything it already
  executed from the queue, so the client can mark them done without re-sending.

### Mac daemon (launchd gui-domain, loopback listener)

- **Start**: bind 127.0.0.1:8788, load tokens, check `tailscale status --json`
  reports BackendState Running and the funnel entry is present; log if not, keep
  serving (the ssh fallback still reaches loopback).
- **Sleep**: nothing to do. The socket dies with the network; the cloud client
  notices within 40 s and starts queueing.
- **Wake**: subscribe to NSWorkspace didWake (or IOKit power notifications). On
  wake: wait for tailscaled to report Running (poll 1 s, up to 30 s), then **drain
  the queue** before accepting new frames: process files in name order, execute each
  once, move to `<queue>/done/`, and record the id in a ring of the last 1000 ids.
  A live frame whose id is in the ring is acked, not re-executed.
- **Roam**: nothing to do in the daemon. tailscaled re-establishes its DERP
  connection; the funnel hostname is unchanged; the cloud client's backoff reconnects.
- **Queue watcher**: the daemon polls the queue folder every 5 s while a socket is
  down and on every wake. It does not use a filesystem watcher. If one is ever
  added, it must exclude `done/` and its own log (F4: the Hammerspoon reload-loop
  incident).

### Fallback selection

1. WSS up: use it for both lanes.
2. WSS down, ssh ControlMaster up: orch lane over ssh; device lane queues (ssh RTT
   through userspace tailscaled is too variable to promise <1 s).
3. Both down: everything queues. The vault sync carries it; the daemon drains on wake.

## Rejected explicitly (beyond the options above)

- **Wait for cloud UDP egress.** Filed, not ours to schedule. Even with UDP, punching
  needs the cloud to originate, and a sandbox with no public endpoint may still fail.
  If it lands, it improves the ssh fallback for free and changes nothing here.
- **Per-request HTTPS instead of a held socket.** Fails the latency budget by TLS
  setup alone.

## Verify before build (open items, none blocking the decision)

- Pick the daemon's funnel port. 8443 is taken by the ssh funnel and 443 was
  deliberately withdrawn from public on 2026-09-12. Confirm the cloud sandbox's
  HTTPS egress allows the chosen port; if only 443 works, ssh and the daemon must
  share 443 behind path or SNI routing (config change, separate lane).
- Confirm `tailscale serve` on the installed version passes WebSocket upgrades to
  the loopback backend. If not, use Funnel's TLS-terminated TCP mode and speak WSS
  directly from the daemon.
- Measure a real click-and-verify round trip through Funnel with a 300 KB screenshot
  to confirm the upload leg stays under the 1-2 s budget.

## Kill switch

Everything this decision leads to can be unexposed with one command and no reboot:

    tailscale funnel --https=<daemon-port> off

The daemon then serves loopback only, reachable by the ssh fallback on 8443.
