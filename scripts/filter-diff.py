"""Replace valid inline Base64 data with metadata in AI context only."""

import base64
import binascii
import hashlib
import re
import sys


DATA_URL = re.compile(
    rb"(?P<header>data:(?:[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+)?"
    rb"(?:;[a-z0-9!#$&^_.+%=-]+)*;base64,)"
    rb"(?P<payload>[a-z0-9+/]+={0,2})(?=[\s\x22\x27<>)}\]`]|$)",
    re.IGNORECASE,
)


def replace_payload(match):
    payload = match["payload"]
    try:
        base64.b64decode(payload, validate=True)
    except binascii.Error:
        return match[0]
    fingerprint = hashlib.sha256(payload).hexdigest()
    return match["header"] + (
        f"[Base64 payload omitted: {len(payload)} encoded bytes; sha256={fingerprint}]"
    ).encode("ascii")


for line in sys.stdin.buffer:
    sys.stdout.buffer.write(DATA_URL.sub(replace_payload, line))
