#!/usr/bin/env python3
"""

Prints 3 tables: ICMP (fping), TCP (net_response), UDP DNS (dns_query).

- ICMP: aggregates last WINDOW_SAMPLES rtt_ms per target into MIN/AVG/MAX and LOSS%.
- TCP/DNS: for the future

Usage:
  python3 scripts/view_tables.py /var/log/telegraf/netprobe_metrics.out
  # or just: python3 scripts/view_tables.py   (uses default path)

Tip:
  watch -n 5 'python3 scripts/view_tables.py /var/log/telegraf/netprobe_metrics.out'
"""
import sys
import time
from collections import defaultdict, deque, OrderedDict

DEFAULT_LOG = "/var/log/telegraf/netprobe_metrics.out"
TAIL_LINES = 800           # how many last lines to consider
WINDOW_SAMPLES = 30        # ICMP: rolling window per target for stats

def unescape(s: str) -> str:
    return s.replace("\\,", ",").replace("\\ ", " ").replace("\\=", "=")

def parse_line(line: str):
    """
    Parse a minimal subset of Influx Line Protocol:
      <measurement>[,<tag_k>=<tag_v>...] <field_k>=<field_v>[,<field_k>=<field_v>...] [timestamp]
    """
    line = line.strip()
    if not line or line.startswith("#") or " " not in line:
        return None
    meta, rest = line.split(" ", 1)

    # fields + optional timestamp
    ts = None
    if " " in rest:
        fields_str, ts_str = rest.split(" ", 1)
        ts_str = ts_str.strip()
        if ts_str.isdigit():
            try:
                ts = int(ts_str)  # ns
            except ValueError:
                ts = None
    else:
        fields_str = rest

    # measurement + tags
    parts = meta.split(",")
    meas = parts[0]
    tags = {}
    for t in parts[1:]:
        if "=" in t:
            k, v = t.split("=", 1)
            tags[unescape(k)] = unescape(v)

    # fields
    fields = {}
    for fv in fields_str.split(","):
        if "=" not in fv:
            continue
        k, v = fv.split("=", 1)
        if v.endswith("i"):
            v = v[:-1]
        try:
            fields[k] = float(v)
        except ValueError:
            fields[k] = v
    return meas, tags, fields, ts

def print_table(title, headers, rows):
    print(f"== {title} ==")
    widths = [max(len(h), *(len(str(r[i])) for r in rows)) if rows else len(h)
              for i, h in enumerate(headers)]
    line = " | ".join(h.ljust(widths[i]) for i, h in enumerate(headers))
    sep  = "-+-".join("-" * widths[i] for i in range(len(headers)))
    print(line)
    print(sep)
    for r in rows:
        out = []
        for i, cell in enumerate(r):
            s = "" if cell is None else str(cell)
            # numbers right align if they look like numbers
            if s.replace(".", "", 1).isdigit():
                out.append(s.rjust(widths[i]))
            else:
                out.append(s.ljust(widths[i]))
        print(" | ".join(out))
    print()

def fmt_num(v, decimals=2, dash="—"):
    if v is None:
        return dash
    try:
        return f"{float(v):.{decimals}f}"
    except Exception:
        return str(v)

def age_s(now_ns, ts_ns):
    if not ts_ns:
        return "—"
    return f"{(now_ns - ts_ns)/1e9:.0f}"

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LOG
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Log file not found: {path}")
        print("Make sure output_file is enabled and Telegraf is running.")
        sys.exit(1)

    lines = lines[-TAIL_LINES:]
    now_ns = int(time.time() * 1e9)

    # ICMP rolling window per target
    win = defaultdict(lambda: deque(maxlen=WINDOW_SAMPLES))
    last_meta = {}  # per target: period_ms/timeout_ms + last ts
    # TCP/DNS keep latest per key
    tcp = OrderedDict()
    dns = OrderedDict()

    for ln in lines:
        p = parse_line(ln)
        if not p:
            continue
        meas, tags, fields, ts = p

        if meas == "netprobe_icmp":
            tgt = tags.get("target")
            if not tgt:
                continue
            # we have single-sample RTT as rtt_ms
            rtt = fields.get("rtt_ms")
            sent = int(fields.get("sent", 0) or 0)
            rcvd = int(fields.get("rcvd", 0) or 0)
            loss = float(fields.get("loss_pct", 0) or 0)
            period = fields.get("period_ms")
            timeout = fields.get("timeout_ms")
            # push to rolling window
            win[tgt].append({
                "rtt_ms": rtt,
                "sent": sent,
                "rcvd": rcvd,
                "loss_pct": loss
            })
            # remember meta for display
            last_meta[tgt] = {"period_ms": period, "timeout_ms": timeout, "ts": ts}

        elif meas == "netprobe_tcp":
            srv = tags.get("server", "")
            prt = tags.get("port", "")
            res = tags.get("result", "")
            key = f"{srv}:{prt}" if (srv or prt) else (srv or prt)
            if not key or key.strip(":") == "":
                continue
            tcp[key] = {
                "TIME(s)": fields.get("response_time"),
                "RESULT": res or "—",
                "AGE(s)": age_s(now_ns, ts)
            }

        elif meas == "netprobe_udp_dns":
            srv = tags.get("server", "")
            dom = tags.get("domain", "")
            rtype = tags.get("record_type", "")
            rcode = tags.get("result", fields.get("result_code", "")) or "—"
            qms = fields.get("query_time_ms")
            if not (srv and dom):
                continue
            key = f"{srv} {dom}"
            dns[key] = {
                "SERVER": srv,
                "DOMAIN": dom,
                "RT": rtype or "—",
                "QTIME(ms)": qms,
                "RCODE/RESULT": rcode,
                "AGE(s)": age_s(now_ns, ts)
            }

    # Build ICMP aggregated rows
    icmp_rows = []
    for tgt, dq in win.items():
        if not dq:
            continue
        # aggregate over window
        rtts = [x["rtt_ms"] for x in dq if isinstance(x["rtt_ms"], (int, float))]
        sent_sum = sum(x["sent"] for x in dq)
        rcvd_sum = sum(x["rcvd"] for x in dq)
        loss_pct = None
        if sent_sum > 0:
            loss_pct = 100.0 * (sent_sum - rcvd_sum) / sent_sum
        elif dq:  # fallback to average of provided loss_pct if any
            vals = [x["loss_pct"] for x in dq if isinstance(x["loss_pct"], (int, float))]
            loss_pct = sum(vals) / len(vals) if vals else None

        rtt_min = min(rtts) if rtts else None
        rtt_max = max(rtts) if rtts else None
        rtt_avg = (sum(rtts) / len(rtts)) if rtts else None

        meta = last_meta.get(tgt, {})
        icmp_rows.append([
            tgt,
            fmt_num(loss_pct, 2),
            fmt_num(rtt_avg, 2),
            fmt_num(rtt_min, 2),
            fmt_num(rtt_max, 2),
            f"{rcvd_sum}/{sent_sum}",
            fmt_num(meta.get("period_ms"), 0),
            fmt_num(meta.get("timeout_ms"), 0),
            age_s(now_ns, meta.get("ts"))
        ])

    # Sort ICMP rows by target for stable view
    icmp_rows.sort(key=lambda r: r[0])

    # Build TCP/DNS rows
    tcp_rows = [[k, fmt_num(v["TIME(s)"], 4), v["RESULT"], v["AGE(s)"]] for k, v in tcp.items()]
    dns_rows = [[v["SERVER"], v["DOMAIN"], v["RT"], fmt_num(v["QTIME(ms)"], 2), v["RCODE/RESULT"], v["AGE(s)"]]
                for v in dns.values()]

    # Print
    print_table(
        f"ICMP (netprobe_icmp) — rolling window per target (N={WINDOW_SAMPLES})",
        ["TARGET", "LOSS%", "AVG(ms)", "MIN", "MAX", "RCVD/SENT", "PERIOD(ms)", "TIMEOUT(ms)", "AGE(s)"],
        icmp_rows
    )
    print_table("TCP (netprobe_tcp via inputs.net_response)", ["SERVER:PORT", "TIME(s)", "RESULT", "AGE(s)"], tcp_rows)
    print_table("UDP DNS (netprobe_udp_dns via inputs.dns_query)", ["SERVER", "DOMAIN", "RT", "QTIME(ms)", "RCODE/RESULT", "AGE(s)"], dns_rows)

if __name__ == "__main__":
    main()
