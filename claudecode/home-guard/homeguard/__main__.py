"""Command line entry point: python3 -m homeguard <command> -c config.toml"""
from __future__ import annotations

import argparse
import logging
import sys
import tempfile
import time

from . import analyzer, notify, receiver
from .collectors import parse_stored_line
from .config import load_config, with_defaults
from .detectors import apply_rules, compile_rules
from .report import build_report


def cmd_receive(cfg, args) -> int:
    receiver.serve(cfg)
    return 0


def cmd_analyze(cfg, args) -> int:
    result = analyzer.run_once(cfg, send=not args.no_notify)
    if args.print or args.no_notify:
        print(result.report)
    logging.info("events=%d alerts=%d notified=%d report=%s",
                 len(result.events), len(result.alerts), len(result.notified), result.report_path)
    return 1 if result.errors else 0


def cmd_test_notify(cfg, args) -> int:
    channels = notify.enabled_channels(cfg)
    if not channels:
        print("config.toml 裡沒有啟用任何通知管道 ([notify.email] / [notify.telegram] enabled = true)")
        return 1
    body = f"🛡 Home Guard 測試通知 {time.strftime('%Y-%m-%d %H:%M')}\n收到這則訊息代表通知設定正確。\n"
    delivered, errors = notify.send_all(cfg, "[Home Guard] 測試通知", body, body)
    print(f"已送出 {delivered}/{len(channels)} 個管道")
    for err in errors:
        print("  失敗:", err)
    return 1 if errors else 0


def cmd_replay(cfg, args) -> int:
    """Run the pattern rules over an exported log file (raw syslog lines), without touching state."""
    events = []
    with open(args.file, encoding="utf-8", errors="replace") as f:
        for line in f:
            stored = line if line.count("\t") >= 2 else f"{time.strftime('%Y-%m-%dT%H:%M:%S')}\t-\t{line}"
            ev = parse_stored_line(stored, args.device)
            if ev:
                events.append(ev)
    alerts = apply_rules(events, compile_rules(cfg))
    now = time.time()
    print(build_report(alerts, events, now, now, learning=False))
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="homeguard", description="Mac mini 裝置 log 收集與異常分析")
    parser.add_argument("-c", "--config", default="config.toml", help="設定檔路徑 (預設 ./config.toml)")
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("receive", help="啟動 syslog 接收器 (常駐)")
    p = sub.add_parser("analyze", help="分析自上次以來的新 log 並發送警報")
    p.add_argument("--no-notify", action="store_true", help="只產生報告並印出,不發通知")
    p.add_argument("--print", action="store_true", help="印出報告")
    sub.add_parser("test-notify", help="發送測試通知")
    p = sub.add_parser("replay", help="用規則掃描一個既有的 log 檔 (不寫入狀態)")
    p.add_argument("file")
    p.add_argument("--device", default="replay")

    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    try:
        cfg = load_config(args.config)
    except FileNotFoundError:
        if args.command != "replay":
            print(f"找不到設定檔 {args.config},請先複製 config.example.toml 為 config.toml", file=sys.stderr)
            return 2
        cfg = with_defaults({"general": {"data_dir": tempfile.gettempdir()}})
    commands = {
        "receive": cmd_receive,
        "analyze": cmd_analyze,
        "test-notify": cmd_test_notify,
        "replay": cmd_replay,
    }
    return commands[args.command](cfg, args)


if __name__ == "__main__":
    sys.exit(main())
