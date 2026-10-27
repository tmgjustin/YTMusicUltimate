import asyncio
import json
import os
import socket
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from homeguard import analyzer, detectors, local_checks  # noqa: E402
from homeguard.collectors import collect_device_logs, parse_log_show_ndjson  # noqa: E402
from homeguard.config import with_defaults  # noqa: E402
from homeguard.models import Event  # noqa: E402
from homeguard.notify import _chunks  # noqa: E402
from homeguard.parser import extract_ip, extract_mac, parse_syslog  # noqa: E402
from homeguard.receiver import SyslogWriter, start_servers  # noqa: E402
from homeguard.state import State  # noqa: E402

NOW = time.time()


def make_cfg(data_dir, **overrides):
    raw = {
        "general": {"data_dir": str(data_dir), "learning_days": 0},
        "devices": [{"name": "router", "ip": "192.168.1.1"}, {"name": "nas", "ip": "192.168.1.10"}],
        "local_mac": {"enabled": False, "disk_usage_percent": 0},
    }
    for section, values in overrides.items():
        raw.setdefault(section, {})
        if isinstance(values, dict):
            raw[section].update(values)
        else:
            raw[section] = values
    return with_defaults(raw)


def ev(text, device="nas", program="sshd"):
    return Event(NOW, device, text, program)


class ParserTests(unittest.TestCase):
    def test_rfc3164(self):
        fac, sev, prog, msg = parse_syslog("<38>Oct 27 10:01:02 nas sshd[123]: Failed password for root from 1.2.3.4 port 22 ssh2")
        self.assertEqual((fac, sev, prog), (4, 6, "sshd"))
        self.assertEqual(msg, "Failed password for root from 1.2.3.4 port 22 ssh2")

    def test_rfc3164_without_host(self):
        _, _, prog, msg = parse_syslog("<6>kernel: [12.3] eth0: link down")
        self.assertEqual((prog, msg), ("kernel", "[12.3] eth0: link down"))

    def test_rfc5424(self):
        _, sev, prog, msg = parse_syslog('<14>1 2026-10-27T10:00:00+08:00 NAS Connection - - [meta x="1"] User [admin] logged in from [10.0.0.5]')
        self.assertEqual((sev, prog), (6, "Connection"))
        self.assertTrue(msg.startswith("User [admin] logged in"))

    def test_plain_message(self):
        self.assertEqual(parse_syslog("Failed password for root from 1.2.3.4")[3], "Failed password for root from 1.2.3.4")

    def test_extract_ip_prefers_keyed(self):
        self.assertEqual(extract_ip("eth0 192.168.1.1 rejected login from 203.0.113.9"), "203.0.113.9")
        self.assertEqual(extract_ip("lease 10.0.0.300 bogus"), "")
        self.assertEqual(extract_ip("Authentication: SUCCEEDED :: Viewer Address: 192.168.1.5"), "192.168.1.5")

    def test_extract_mac(self):
        self.assertEqual(extract_mac("DHCPACK(br0) 192.168.1.50 AA-BB-CC-DD-EE-01 phone"), "aa:bb:cc:dd:ee:01")
        self.assertEqual(extract_mac("no mac here 12:34"), "")


class RuleTests(unittest.TestCase):
    def setUp(self):
        self.cfg = make_cfg("/tmp")
        self.rules = detectors.compile_rules(self.cfg)

    def test_brute_force_threshold(self):
        lines = [ev(f"Failed password for root from 203.0.113.7 port {p} ssh2") for p in range(5)]
        alerts = detectors.apply_rules(lines, self.rules)
        bf = [a for a in alerts if a.rule_id == "brute_force"]
        self.assertEqual(len(bf), 1)
        self.assertEqual((bf[0].group, bf[0].count, bf[0].severity), ("203.0.113.7", 5, "critical"))
        self.assertIn("user=root", bf[0].detail)
        self.assertFalse([a for a in detectors.apply_rules(lines[:4], self.rules) if a.rule_id == "brute_force"])

    def test_disk_error_and_reboot(self):
        alerts = detectors.apply_rules(
            [ev("ata1.00: I/O error, dev sda, sector 123", program="kernel"), ev("System started up", device="router", program="")],
            self.rules,
        )
        self.assertEqual({a.rule_id for a in alerts}, {"disk_error", "reboot"})

    def test_custom_rule_override_and_disable(self):
        cfg = make_cfg("/tmp", rules=[
            {"id": "reboot", "enabled": False},
            {"id": "vpn", "title": "VPN", "pattern": "(?i)vpn up", "severity": "info", "devices": "^router$"},
        ])
        rules = detectors.compile_rules(cfg)
        ids = {r.id for r in rules}
        self.assertNotIn("reboot", ids)
        alerts = detectors.apply_rules([ev("VPN up", device="router"), ev("VPN up", device="nas")], rules)
        self.assertEqual([(a.rule_id, a.device) for a in alerts], [("vpn", "router")])


class DetectorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = State(os.path.join(self.tmp.name, "s.db"))
        self.cfg = make_cfg(self.tmp.name)

    def tearDown(self):
        self.state.close()
        self.tmp.cleanup()

    def test_new_login_ip(self):
        line = ev("Accepted publickey for admin from 198.51.100.4 port 5000 ssh2")
        self.assertEqual(detectors.detect_new_login_ips([line], self.state, self.cfg, True, NOW), [])
        # learnt during learning period -> no alert later
        self.assertEqual(detectors.detect_new_login_ips([line], self.state, self.cfg, False, NOW), [])
        other = ev("Accepted password for admin from 198.51.100.99 port 5000 ssh2")
        alerts = detectors.detect_new_login_ips([other, other], self.state, self.cfg, False, NOW)
        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0].severity, "warning")
        internal = ev("Accepted password for admin from 192.168.1.20 port 5000 ssh2")
        self.assertEqual(detectors.detect_new_login_ips([internal], self.state, self.cfg, False, NOW)[0].severity, "info")

    def test_new_mac_skips_known(self):
        cfg = make_cfg(self.tmp.name, detect={"known_macs": {"AA:BB:CC:DD:EE:01": "phone"}})
        lines = [
            ev("DHCPACK(br0) 192.168.1.50 aa:bb:cc:dd:ee:01 phone", device="router", program="dnsmasq-dhcp"),
            ev("DHCPACK(br0) 192.168.1.51 aa:bb:cc:dd:ee:02 unknown", device="router", program="dnsmasq-dhcp"),
        ]
        alerts = detectors.detect_new_macs(lines, self.state, cfg, False, NOW)
        self.assertEqual([a.group for a in alerts], ["aa:bb:cc:dd:ee:02"])
        self.assertEqual(detectors.detect_new_macs(lines, self.state, cfg, False, NOW), [])

    def test_volume_spike(self):
        for _ in range(30):
            self.state.update_volume("nas", time.localtime(NOW).tm_hour, 2.0)  # 2 lines / minute
        normal = [ev("x")] * 30
        self.assertEqual(detectors.detect_volume(normal, self.state, self.cfg, ["nas"], NOW, 15), [])
        spike = [ev(f"error {i}") for i in range(600)]
        alerts = detectors.detect_volume(spike, self.state, self.cfg, ["nas"], NOW, 15)
        self.assertEqual(len(alerts), 1)
        self.assertIn("error #", alerts[0].samples[0])

    def test_silence(self):
        self.state.touch_device("router", NOW - 3 * 3600)
        self.state.touch_device("nas", NOW - 60)
        alerts = detectors.detect_silence(self.state, self.cfg, NOW, NOW - 86400)
        self.assertEqual([a.device for a in alerts], ["router"])

    def test_launch_items_baseline_then_new(self):
        d = Path(self.tmp.name) / "LaunchDaemons"
        d.mkdir()
        (d / "com.old.plist").write_bytes(b"")
        self.assertEqual(local_checks.check_launch_items(self.state, "mac", NOW, dirs=[str(d)]), [])
        import plistlib
        (d / "com.evil.plist").write_bytes(plistlib.dumps({"Label": "x", "ProgramArguments": ["/tmp/evil"]}))
        alerts = local_checks.check_launch_items(self.state, "mac", NOW, dirs=[str(d)])
        self.assertEqual(len(alerts), 1)
        self.assertIn("/tmp/evil", alerts[0].detail)


class CollectorTests(unittest.TestCase):
    def test_log_show_ndjson(self):
        text = "\n".join([
            json.dumps({"timestamp": "2026-10-27 10:00:01.123456+0800", "eventMessage": "Failed password for bob from 203.0.113.1",
                        "processImagePath": "/usr/sbin/sshd", "messageType": "Default"}),
            json.dumps({"count": 1, "finished": 1}),
        ])
        events = parse_log_show_ndjson(text, "mac-mini")
        self.assertEqual(len(events), 1)
        self.assertEqual((events[0].program, events[0].severity), ("sshd", 5))

    def test_incremental_read(self):
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp) / "logs"
            writer = SyslogWriter(logs, {"192.168.1.10": "nas"})
            writer.write("192.168.1.10", "<38>nas sshd[1]: hello")
            state = State(os.path.join(tmp, "s.db"))
            self.assertEqual(len(collect_device_logs(logs, state)), 1)
            self.assertEqual(collect_device_logs(logs, state), [])
            writer.write("192.168.1.10", "<38>nas sshd[1]: again")
            writer.write("10.9.9.9", "<38>who: me")
            events = collect_device_logs(logs, state)
            self.assertEqual(sorted(e.device for e in events), ["nas", "unknown-10.9.9.9"])
            writer.close()
            state.close()


class ReceiverTests(unittest.TestCase):
    def test_udp_and_tcp(self):
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp) / "logs"
            writer = SyslogWriter(logs, {"127.0.0.1": "local"})
            ports = []
            for _ in range(2):
                with socket.socket() as s:
                    s.bind(("127.0.0.1", 0))
                    ports.append(s.getsockname()[1])
            cfg = {"receiver": {"listen": "127.0.0.1", "udp_port": ports[0], "tcp_port": ports[1]}}

            async def scenario():
                servers = await start_servers(cfg, writer)
                udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                udp.sendto(b"<13>Oct 27 10:00:00 host app: via udp", ("127.0.0.1", ports[0]))
                udp.close()
                reader, w = await asyncio.open_connection("127.0.0.1", ports[1])
                w.write(b"<13>app: via tcp newline\n")
                framed = b"<13>app: via tcp octet"
                w.write(str(len(framed)).encode() + b" " + framed)
                await w.drain()
                w.close()
                await asyncio.sleep(0.3)
                for s in servers:
                    s.close()

            asyncio.run(scenario())
            writer.close()
            content = "".join(p.read_text() for p in logs.glob("local/*.log"))
            for needle in ("via udp", "via tcp newline", "via tcp octet"):
                self.assertIn(needle, content)


class EndToEndTests(unittest.TestCase):
    def test_run_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = make_cfg(tmp)
            writer = SyslogWriter(Path(tmp) / "logs", {"192.168.1.10": "nas", "192.168.1.1": "router"})
            for port in range(6):
                writer.write("192.168.1.10", f"<38>nas sshd[1]: Failed password for root from 203.0.113.7 port {port} ssh2")
            writer.write("192.168.1.1", "<30>router kernel: eth1: link down")
            sent = []

            def sender(subject, body, short):
                sent.append((subject, body, short))
                return 1, []

            result = analyzer.run_once(cfg, now=time.time(), sender=sender)
            self.assertEqual(len(sent), 1)
            self.assertIn("暴力破解", sent[0][0])
            self.assertIn("203.0.113.7", sent[0][1])
            self.assertTrue(result.report_path.exists())

            # same attack again within cooldown -> reported as suppressed, not re-sent
            for port in range(6):
                writer.write("192.168.1.10", f"<38>nas sshd[1]: Failed password for root from 203.0.113.7 port {port} ssh2")
            result = analyzer.run_once(cfg, now=time.time() + 60, sender=sender)
            self.assertEqual(len(sent), 1)
            self.assertTrue(all(a.suppressed for a in result.alerts if a.rule_id == "brute_force"))
            writer.close()

    def test_failed_delivery_is_retried(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = make_cfg(tmp)
            writer = SyslogWriter(Path(tmp) / "logs", {"192.168.1.10": "nas"})
            writer.write("192.168.1.10", "<38>nas kernel: ata1: I/O error")
            analyzer.run_once(cfg, sender=lambda s, b, sb: (0, ["down"]))
            writer.write("192.168.1.10", "<38>nas kernel: ata1: I/O error")
            calls = []
            analyzer.run_once(cfg, now=time.time() + 60, sender=lambda s, b, sb: calls.append(s) or (1, []))
            self.assertEqual(len(calls), 1)
            writer.close()


class NotifyTests(unittest.TestCase):
    def test_chunks(self):
        text = "a" * 9000 + "\nshort\n"
        chunks = _chunks(text, 4000)
        self.assertTrue(all(len(c) <= 4000 for c in chunks))
        self.assertEqual("".join(chunks), text)


if __name__ == "__main__":
    unittest.main()
