"""
Solti _notifier_base: multi-channel event dispatch library.

Usage in a sensor script:
    import sys
    sys.path.insert(0, '/usr/local/lib/solti')
    import notifier

    event = notifier.event("my_sensor", "warn", "Something happened", {"count": 42})
    notifier.notify_with_cooldown(event, config)

Event dict schema:
    {
        "source":    str   # sensor name, used as cooldown key
        "severity":  str   # info | warn | error | critical
        "summary":   str   # one-line human-readable
        "detail":    dict  # source-specific structured data (optional)
        "timestamp": int   # unix epoch (set automatically)
    }

Config dict schema (from config.yml):
    state_dir:        str   # path for cooldown state files
    cooldown_minutes: int   # suppress repeat notifications
    channels:
        email:   {enabled, host, port, username, password, from_address, recipients}
        matrix:  {enabled, homeserver, token, room_id}
        redis:   {enabled, url, channel}
        amqp:    {enabled, url, exchange, routing_key}
"""

import json
import os
import smtplib
import time
from email.message import EmailMessage


def event(source, severity, summary, detail=None):
    """Build a standard event dict."""
    return {
        "source": source,
        "severity": severity,
        "summary": summary,
        "detail": detail or {},
        "timestamp": int(time.time()),
    }


def notify(ev, config):
    """Dispatch event to all enabled channels. Errors in one channel do not stop others."""
    channels = config.get("channels", {})
    dispatched = 0

    if channels.get("email", {}).get("enabled"):
        _smtp_send(ev, channels["email"])
        dispatched += 1

    if channels.get("matrix", {}).get("enabled"):
        _matrix_post(ev, channels["matrix"])
        dispatched += 1

    if channels.get("redis", {}).get("enabled"):
        _redis_publish(ev, channels["redis"])
        dispatched += 1

    if channels.get("amqp", {}).get("enabled"):
        _amqp_publish(ev, channels["amqp"])
        dispatched += 1

    if dispatched == 0:
        print("notifier: WARNING: no channels enabled — event not dispatched")


def notify_with_cooldown(ev, config):
    """notify() wrapped with per-source/severity cooldown. Returns True if dispatched."""
    state_dir = config.get("state_dir", "/var/lib/notifier")
    cooldown_minutes = config.get("cooldown_minutes", 60)

    if _check_cooldown(ev["source"], ev["severity"], state_dir, cooldown_minutes):
        print(f"notifier: suppressed (cooldown active for {ev['source']}/{ev['severity']})")
        return False

    notify(ev, config)
    _update_cooldown(ev["source"], ev["severity"], state_dir)
    return True


def _check_cooldown(source, severity, state_dir, cooldown_minutes):
    state_file = os.path.join(state_dir, f"{source}_{severity}.state")
    if not os.path.exists(state_file):
        return False
    try:
        with open(state_file) as f:
            last = float(f.read().strip())
        return (time.time() - last) < (cooldown_minutes * 60)
    except (ValueError, OSError):
        return False


def _update_cooldown(source, severity, state_dir):
    os.makedirs(state_dir, exist_ok=True)
    state_file = os.path.join(state_dir, f"{source}_{severity}.state")
    with open(state_file, "w") as f:
        f.write(str(time.time()))


# ── Channel handlers ─────────────────────────────────────────────────────────

def _smtp_send(ev, cfg):
    try:
        subject = f"[{ev['severity'].upper()}] {ev['source']}: {ev['summary']}"
        body = ev["summary"]
        if ev.get("detail"):
            body += f"\n\n{json.dumps(ev['detail'], indent=2)}"
        body += f"\n\n--\ntimestamp: {time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime(ev['timestamp']))}"

        msg = EmailMessage()
        msg["Subject"] = subject
        msg["From"] = cfg["from_address"]
        msg["To"] = cfg["recipients"]
        msg.set_content(body)

        with smtplib.SMTP(cfg["host"], cfg["port"]) as smtp:
            smtp.starttls()
            smtp.login(cfg["username"], cfg["password"])
            smtp.send_message(msg)
        print(f"notifier: email sent to {cfg['recipients']}")
    except Exception as e:
        print(f"notifier: email ERROR: {e}")


def _matrix_post(ev, cfg):
    try:
        import requests

        body = f"[{ev['severity'].upper()}] {ev['source']}: {ev['summary']}"
        if ev.get("detail"):
            body += f"\n{json.dumps(ev['detail'], indent=2)}"

        homeserver = cfg["homeserver"].rstrip("/")
        room_id = cfg["room_id"]
        txn_id = str(int(time.time() * 1000))
        url = f"{homeserver}/_matrix/client/r0/rooms/{room_id}/send/m.room.message/{txn_id}"

        r = requests.put(
            url,
            json={"msgtype": "m.text", "body": body},
            headers={"Authorization": f"Bearer {cfg['token']}"},
            timeout=10,
        )
        r.raise_for_status()
        print(f"notifier: matrix sent to {room_id}")
    except Exception as e:
        print(f"notifier: matrix ERROR: {e}")


def _redis_publish(ev, cfg):
    try:
        import redis as redis_lib

        r = redis_lib.from_url(cfg["url"])
        channel = cfg.get("channel", "solti_events")
        r.publish(channel, json.dumps(ev))
        print(f"notifier: redis published to {channel}")
    except Exception as e:
        print(f"notifier: redis ERROR: {e}")


def _amqp_publish(ev, cfg):
    try:
        import pika

        params = pika.URLParameters(cfg["url"])
        conn = pika.BlockingConnection(params)
        ch = conn.channel()
        exchange = cfg.get("exchange", "solti_events")
        routing_key = cfg.get("routing_key", ev.get("source", "event"))
        ch.basic_publish(
            exchange=exchange,
            routing_key=routing_key,
            body=json.dumps(ev),
            properties=pika.BasicProperties(content_type="application/json"),
        )
        conn.close()
        print(f"notifier: amqp published to {exchange}/{routing_key}")
    except Exception as e:
        print(f"notifier: amqp ERROR: {e}")
