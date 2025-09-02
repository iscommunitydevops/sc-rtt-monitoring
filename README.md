# NetProbe Telegraf (minimal custom code)

Minimal monitoring of **RTT** and **packet loss** using:
- **ICMP**: `fping -C` via Telegraf `[[inputs.exec]]` 
- **TCP**: Telegraf `[[inputs.net_response]]` (connect latency + result).
- **UDP**: Telegraf `[[inputs.dns_query]]` (UDP DNS query latency).

## Quick start (on a Linux server)
```bash
sudo bash ./install.sh

# Quick check of ICMP script without Telegraf:
sudo /opt/netprobe/scripts/fping2influx.sh --dry-run

# One-shot Telegraf for diagnostics:
sudo telegraf --once

## Where to set targets

/etc/telegraf/netprobe.env

## Metrics format

ICMP (measurement netprobe_icmp)
Tags: target, proto=ICMP (+ your NP_TAGS).
Fields: sent, rcvd, loss_pct, rtt_min_ms, rtt_avg_ms, rtt_max_ms, rtt_stdev_ms.

TCP (measurement netprobe_tcp) — from net_response
Fields: response_time (seconds), result.
Tags: server, port, protocol.

UDP DNS (measurement netprobe_udp_dns) — from dns_query
Fields: query_time_ms, result_code, rcode_value.
Tags: server, domain, record_type, result.

## License

MIT

