"""Reachability probing.

A probe that calls a healthy host dead is worse than no probe, because the run
skips a source it could have read. Most of these tests exist for that failure
direction.
"""

from __future__ import annotations

import socket
from unittest.mock import MagicMock, patch

from dghs.source_health import Reachability, SourceHealth, check_sources, probe


class TestProbe:
    def test_a_host_that_accepts_is_reachable(self):
        with patch("socket.create_connection") as connect:
            health = probe("https://example.invalid/")
        assert health.is_up
        assert health.reachability is Reachability.REACHABLE
        connect.assert_called_once()

    def test_it_does_not_force_ipv4(self):
        # Forcing AF_INET reported dashboard.dghs.gov.bd as timing out on a
        # NAT64 network, where the IPv4 literal does not route but the
        # synthesised IPv6 address connects immediately.
        with patch("socket.create_connection") as connect:
            probe("https://example.invalid/")
        args, kwargs = connect.call_args
        assert args[0] == ("example.invalid", 443)
        assert "timeout" in kwargs
        # create_connection resolves all families itself; nothing pins a family.
        assert not any(a in (socket.AF_INET, socket.AF_INET6) for a in args)

    def test_a_timeout_is_reported_as_timeout(self):
        with patch("socket.create_connection", side_effect=socket.timeout()):
            health = probe("https://example.invalid/")
        assert not health.is_up
        assert health.reachability is Reachability.TIMEOUT

    def test_a_refusal_is_distinguished_from_a_timeout(self):
        # Different causes, different fixes: refused means the host answered.
        with patch("socket.create_connection", side_effect=ConnectionRefusedError("no")):
            health = probe("https://example.invalid/")
        assert health.reachability is Reachability.REFUSED

    def test_dns_failure_is_not_retried(self):
        with patch("socket.create_connection",
                   side_effect=socket.gaierror("name unknown")) as connect:
            health = probe("https://nowhere.invalid/")
        assert health.reachability is Reachability.DNS_FAILURE
        assert connect.call_count == 1, "a name that does not resolve will not resolve on retry"

    def test_a_transient_failure_is_retried_before_being_believed(self):
        attempts = [socket.timeout(), None]
        def flaky(*args, **kwargs):
            outcome = attempts.pop(0)
            if outcome: raise outcome
            return MagicMock()
        with patch("socket.create_connection", side_effect=flaky):
            health = probe("https://example.invalid/")
        assert health.is_up, "one dropped packet must not condemn a live host"

    def test_the_port_follows_the_scheme(self):
        with patch("socket.create_connection") as connect:
            probe("http://example.invalid/")
        assert connect.call_args[0][0][1] == 80

    def test_a_bare_hostname_works(self):
        with patch("socket.create_connection") as connect:
            probe("example.invalid")
        assert connect.call_args[0][0] == ("example.invalid", 443)


class TestCheckSources:
    def test_both_up(self):
        with patch("socket.create_connection"):
            health = check_sources("https://a.invalid/", "https://b.invalid/")
        assert all(h.is_up for h in health.values())

    def test_press_release_down_dashboard_up_is_partial_not_fatal(self, caplog):
        def selective(address, timeout=None):
            if address[0] == "old.invalid":
                raise socket.timeout()
            return MagicMock()
        with patch("socket.create_connection", side_effect=selective):
            health = check_sources("https://old.invalid/", "https://dash.invalid/")
        assert not health["press_release"].is_up
        assert health["dashboard"].is_up

    def test_both_down_is_reported_as_an_error(self, caplog):
        import logging
        with caplog.at_level(logging.ERROR):
            with patch("socket.create_connection", side_effect=socket.timeout()):
                check_sources("https://a.invalid/", "https://b.invalid/")
        assert any("Both DGHS surfaces are unreachable" in r.message for r in caplog.records)


def test_tcp_reachable_does_not_promise_a_working_page():
    # Observed live: the dashboard accepted TCP while HTTP reads timed out.
    # The probe answers only "is it accepting connections", which is why the
    # fetch layer keeps its own retries.
    health = SourceHealth("example.invalid", Reachability.REACHABLE)
    assert health.is_up
    assert "http" not in health.as_dict()


def test_health_serialises_for_the_run_log():
    health = SourceHealth("h.invalid", Reachability.TIMEOUT, "no response", 8.0)
    assert health.as_dict() == {
        "host": "h.invalid", "reachability": "timeout",
        "detail": "no response", "elapsedSeconds": 8.0,
    }
