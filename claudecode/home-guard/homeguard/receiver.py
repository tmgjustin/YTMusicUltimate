"""Syslog receiver (UDP + TCP) that network devices push their logs to.

Each line is stored as `<received ISO time>\\t<sender IP>\\t<raw syslog>` in
`<data_dir>/logs/<device>/<YYYY-MM-DD>.log`, so the analyzer can read new lines
incrementally and the raw logs stay greppable.
"""
from __future__ import annotations

import asyncio
import logging
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, Tuple

log = logging.getLogger(__name__)

MAX_LINE = 64 * 1024
_UNSAFE = re.compile(r"[^\w.\-]")


def device_map(cfg) -> Dict[str, str]:
    return {ip: dev["name"] for dev in cfg["devices"] for ip in dev["ips"]}


class SyslogWriter:
    def __init__(self, logs_dir: Path, devices_by_ip: Dict[str, str]):
        self.logs_dir = Path(logs_dir)
        self.devices_by_ip = devices_by_ip
        self._files: Dict[str, Tuple[str, object]] = {}

    def device_for(self, ip: str) -> str:
        if ip.startswith("::ffff:"):
            ip = ip[7:]
        name = self.devices_by_ip.get(ip) or f"unknown-{ip}"
        return _UNSAFE.sub("_", name)

    def write(self, src_ip: str, raw: str, now: Optional[datetime] = None) -> None:
        raw = raw.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip()
        if not raw:
            return
        now = now or datetime.now().astimezone()
        device = self.device_for(src_ip)
        day = now.strftime("%Y-%m-%d")
        cached = self._files.get(device)
        if cached is None or cached[0] != day:
            if cached is not None:
                cached[1].close()
            path = self.logs_dir / device / f"{day}.log"
            path.parent.mkdir(parents=True, exist_ok=True)
            cached = (day, open(path, "a", encoding="utf-8"))
            self._files[device] = cached
        fh = cached[1]
        fh.write(f"{now.isoformat(timespec='seconds')}\t{src_ip}\t{raw}\n")
        fh.flush()

    def close(self) -> None:
        for _, fh in self._files.values():
            fh.close()
        self._files.clear()


class _UDPProtocol(asyncio.DatagramProtocol):
    def __init__(self, writer: SyslogWriter):
        self.writer = writer

    def datagram_received(self, data: bytes, addr) -> None:
        text = data.decode("utf-8", "replace")
        for line in text.splitlines() or [text]:
            self.writer.write(addr[0], line)


async def _handle_tcp(writer: SyslogWriter, reader: asyncio.StreamReader, conn: asyncio.StreamWriter) -> None:
    peer = conn.get_extra_info("peername")[0]
    buf = b""
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            buf += chunk
            # RFC 6587: octet-counting ("LEN msg") or newline-delimited framing.
            while buf:
                m = re.match(rb"(\d{1,6}) ", buf)
                if m:
                    length = int(m.group(1))
                    end = m.end() + length
                    if len(buf) < end:
                        break
                    msg, buf = buf[m.end():end], buf[end:]
                else:
                    nl = buf.find(b"\n")
                    if nl < 0:
                        if len(buf) > MAX_LINE:
                            msg, buf = buf, b""
                        else:
                            break
                    else:
                        msg, buf = buf[:nl], buf[nl + 1:]
                writer.write(peer, msg.decode("utf-8", "replace"))
        if buf.strip():
            writer.write(peer, buf.decode("utf-8", "replace"))
    except (ConnectionError, asyncio.IncompleteReadError):
        pass
    finally:
        conn.close()


async def start_servers(cfg, writer: SyslogWriter):
    rcv = cfg["receiver"]
    loop = asyncio.get_running_loop()
    servers = []
    if rcv.get("udp_port"):
        transport, _ = await loop.create_datagram_endpoint(
            lambda: _UDPProtocol(writer), local_addr=(rcv["listen"], rcv["udp_port"])
        )
        servers.append(transport)
        log.info("listening on udp %s:%s", rcv["listen"], rcv["udp_port"])
    if rcv.get("tcp_port"):
        server = await asyncio.start_server(
            lambda r, w: _handle_tcp(writer, r, w), rcv["listen"], rcv["tcp_port"]
        )
        servers.append(server)
        log.info("listening on tcp %s:%s", rcv["listen"], rcv["tcp_port"])
    return servers


def serve(cfg) -> None:
    logs_dir = Path(cfg["general"]["data_dir"]).expanduser() / "logs"
    writer = SyslogWriter(logs_dir, device_map(cfg))

    async def main():
        await start_servers(cfg, writer)
        await asyncio.Event().wait()

    try:
        asyncio.run(main())
    finally:
        writer.close()
