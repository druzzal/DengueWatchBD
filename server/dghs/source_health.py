"""Is a DGHS host actually reachable, and what should the run do if not.

The press-release host has been refusing TCP connections for days at a time.
Without a check, every missing day pays the full retry budget — three attempts
at a 45-second timeout each — so a run that can achieve nothing still takes a
quarter of an hour and buries the real message under hundreds of identical
warnings.

One cheap probe up front answers the question the retries were asking
repeatedly, and lets the run say plainly that the source is down rather than
implying the data simply has not changed.
"""

from __future__ import annotations

import logging
import socket
import time
from dataclasses import dataclass
from enum import Enum
from urllib.parse import urlparse

LOG = logging.getLogger("dghs.health")

PROBE_TIMEOUT = 8      # a reachable host answers in well under this
PROBE_ATTEMPTS = 2     # one retry, so a single dropped packet is not a verdict


class Reachability(str, Enum):
    REACHABLE = "reachable"
    TIMEOUT = "timeout"            # host is routed but nothing answers
    REFUSED = "refused"            # host answered, port closed
    DNS_FAILURE = "dns_failure"    # name does not resolve
    ERROR = "error"

    @property
    def is_up(self) -> bool:
        return self is Reachability.REACHABLE


@dataclass(frozen=True)
class SourceHealth:
    host: str
    reachability: Reachability
    detail: str = ""
    elapsed: float = 0.0

    @property
    def is_up(self) -> bool:
        return self.reachability.is_up

    def log(self) -> None:
        """One clear line, at a level that matches what it means."""
        if self.is_up:
            LOG.info("[health] %s is reachable (%.1fs)", self.host, self.elapsed)
            return
        LOG.warning(
            "[health] %s is NOT reachable: %s (%s, %.1fs). "
            "Days that need this host will be skipped rather than retried; "
            "the last good data stays published.",
            self.host, self.reachability.value, self.detail or "no detail",
            self.elapsed,
        )

    def as_dict(self) -> dict:
        return {
            "host": self.host,
            "reachability": self.reachability.value,
            "detail": self.detail,
            "elapsedSeconds": round(self.elapsed, 2),
        }


def probe(url_or_host: str, port: int | None = None,
          timeout: float = PROBE_TIMEOUT,
          attempts: int = PROBE_ATTEMPTS) -> SourceHealth:
    """TCP-connect to a host and classify the result.

    A TCP probe rather than an HTTP request on purpose: this asks only whether
    the server is accepting connections, so it cannot be confused by a slow
    page, a redirect, or a 403 from a host that is perfectly alive.
    """
    parsed = urlparse(url_or_host if "//" in url_or_host else f"//{url_or_host}")
    host = parsed.hostname or url_or_host
    target_port = port or (443 if parsed.scheme in ("https", "") else 80)

    started = time.monotonic()
    last = ""
    for attempt in range(1, attempts + 1):
        sock = None
        try:
            # create_connection, not socket(AF_INET). It walks whatever
            # getaddrinfo returns, in order, across address families.
            #
            # Forcing IPv4 here reported dashboard.dghs.gov.bd as timing out on
            # a NAT64 network, where the IPv4 literal does not route but the
            # synthesised IPv6 address connects in a tenth of a second. A probe
            # that calls a healthy host dead is worse than no probe, because the
            # run would skip a source it could have read.
            sock = socket.create_connection((host, target_port), timeout=timeout)
            return SourceHealth(host, Reachability.REACHABLE,
                                elapsed=time.monotonic() - started)
        except socket.timeout:
            last = f"no response within {timeout}s"
            outcome = Reachability.TIMEOUT
        except ConnectionRefusedError as exc:
            last = str(exc)
            outcome = Reachability.REFUSED
        except socket.gaierror as exc:
            # Name resolution does not improve on retry.
            return SourceHealth(host, Reachability.DNS_FAILURE, str(exc),
                                time.monotonic() - started)
        except OSError as exc:
            last = str(exc)
            outcome = Reachability.ERROR
        finally:
            if sock is not None:
                sock.close()

        if attempt < attempts:
            LOG.debug("[health] %s attempt %d/%d: %s", host, attempt, attempts, last)

    return SourceHealth(host, outcome, last, time.monotonic() - started)


def check_sources(press_release_url: str, dashboard_url: str) -> dict[str, SourceHealth]:
    """Probe both DGHS surfaces and report what the run can still do."""
    health = {
        "press_release": probe(press_release_url),
        "dashboard": probe(dashboard_url),
    }
    for source in health.values():
        source.log()

    if not health["press_release"].is_up and not health["dashboard"].is_up:
        LOG.error("[health] Both DGHS surfaces are unreachable. Nothing can be "
                  "ingested this run; the published dataset is left untouched.")
    elif not health["press_release"].is_up:
        LOG.warning("[health] Press releases are unreachable but the dashboard "
                    "is up: national totals can still be refreshed, per-district "
                    "figures cannot.")
    return health
