"""Replace recognized Base64 data URL payloads in AI context, never bare Base64."""

import base64
import binascii
import hashlib
import html
import re
import sys
from urllib.parse import unquote_to_bytes


def source_character(character):
    alternatives = [b"(?i:" + re.escape(character.encode("ascii")) + b")"]
    for value in sorted({ord(character.lower()), ord(character.upper())}):
        hexadecimal = b"(?i:" + f"{value:02x}".encode("ascii") + b")"
        alternatives.extend((
            rb"\\+(?:u00" + hexadecimal + b"|x" + hexadecimal + b")",
            b"&#0*" + str(value).encode("ascii") + b";",
            b"&#[xX]0*" + hexadecimal + b";",
        ))
    if character == ":":
        alternatives.append(b"&colon;")
    return b"(?:" + b"|".join(alternatives) + b")"


START = re.compile(b"".join(source_character(character) for character in "data:"))
TOKEN = rb"[a-z0-9!#$%&'*+.^_`|~-]+"
HEADER = re.compile(
    rb"(?:" + TOKEN + rb"/" + TOKEN + rb")?"
    rb"(?: *; *" + TOKEN + rb" *= *(?:" + TOKEN + rb'|"[^"\r\n]*"))*'
    rb" *; *base64 *,",
    re.IGNORECASE,
)
HEADER_RUN = re.compile(rb"[a-zA-Z0-9!#$%*+./:;=?^_|~-]+")
BODY_RUN = re.compile(rb"[a-zA-Z0-9+/=]+")
URL_RUN = re.compile(rb"[^\\&\s\"'`<>()}\]]+")
ESCAPE = re.compile(
    rb"\\+(?P<code>u00[0-9a-fA-F]{2}|x[0-9a-fA-F]{2}|[\\/'\"nrtfbv]|\r?\n)"
)
ENTITY = re.compile(rb"&(?:#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]+);")
WHITESPACE = b" \t\n\r\f"
QUOTES = b"\"'`"
ESCAPED_WHITESPACE = {
    b"n": b"\n", b"r": b"\r", b"t": b"\t", b"f": b"\f", b"b": b"\b", b"v": b"\v"
}


def read_unit(data, position):
    """Decode one literal source unit without executing or rewriting source."""
    if data[position:position + 1] == b"\\":
        match = ESCAPE.match(data, position)
        if match:
            code = match["code"]
            if code.startswith((b"u", b"x")):
                value = bytes([int(code[3:] if code.startswith(b"u") else code[1:], 16)])
            elif code.endswith(b"\n"):
                value = b""  # A JavaScript line continuation contributes no content.
            else:
                value = ESCAPED_WHITESPACE.get(code, code)
            return value, match.end()
    elif data[position:position + 1] == b"&":
        match = ENTITY.match(data, position)
        if match:
            value = html.unescape(match[0].decode("ascii"))
            if len(value) == 1 and ord(value) < 128:
                return value.encode("ascii"), match.end()
    return data[position:position + 1], position + 1


def skip_layout(data, position, prefix):
    while position < len(data) and data[position] in WHITESPACE:
        newline = data[position] == 10
        position += 1
        if newline and prefix and position < len(data):
            # Never join added, removed, or context lines from different versions.
            if data[position:position + 1] != prefix:
                return None
            position += 1
    return position


def literal_join(data, position, prefix, quote):
    closing, end = read_unit(data, position)
    if closing not in (b'"', b"'", b"`") or (quote and closing != quote):
        return None
    end = skip_layout(data, end, prefix)
    if end is None or data[end:end + 1] != b"+":
        return None
    end = skip_layout(data, end + 1, prefix)
    if end is None or end == len(data):
        return None
    opening, end = read_unit(data, end)
    if opening in (b'"', b"'", b"`"):
        return end, opening
    return None


def read_header(data, position, prefix, quote):
    header = bytearray()
    parameter_quote = False
    while position < len(data):
        if not parameter_quote:
            joined = literal_join(data, position, prefix, quote)
            if joined:
                position, quote = joined
                continue
        run = HEADER_RUN.match(data, position)
        if run:
            header.extend(run[0])
            position = run.end()
            continue
        value, end = read_unit(data, position)
        if value == b"," and not parameter_quote:
            header.extend(value)
            if HEADER.fullmatch(header):
                return end, quote
            return None
        if value == b'"':
            if parameter_quote or header.rstrip().endswith(b"="):
                parameter_quote = not parameter_quote
            else:
                return None
        elif value in (b"'", b"`") and value == quote and not parameter_quote:
            return None
        elif value and value[0] in WHITESPACE:
            end = skip_layout(data, position, prefix) if data[position] in WHITESPACE else end
            if end is None:
                return None
            value = b" "
        elif value in (b"<", b">", b"\\"):
            return None
        header.extend(value)
        position = end
    return None


def valid_base64(encoded):
    # Match the web's forgiving Base64 rules, without accepting malformed padding.
    unpadded = encoded
    if len(unpadded) % 4 == 0:
        if unpadded.endswith(b"=="):
            unpadded = unpadded[:-2]
        elif unpadded.endswith(b"="):
            unpadded = unpadded[:-1]
    if len(unpadded) % 4 == 1 or b"=" in unpadded:
        return False
    try:
        base64.b64decode(unpadded + b"=" * (-len(unpadded) % 4), validate=True)
        return True
    except binascii.Error:
        return False


def url_end(data, position, prefix, quote):
    """Skip fragments or rejected bodies so their contents are never re-filtered."""
    while position < len(data):
        run = URL_RUN.match(data, position)
        if run:
            position = run.end()
            continue
        joined = literal_join(data, position, prefix, quote)
        if joined:
            position, quote = joined
            continue
        value, end = read_unit(data, position)
        if value and value[0] in WHITESPACE:
            if not quote:
                break
            if data[position] in WHITESPACE:
                end = skip_layout(data, position, prefix)
                if end is None:
                    break
        elif value in (b'"', b"'", b"`") and (not quote or value == quote):
            if data[position:position + 1] != b"&":
                break
        elif not quote and value in (b"<", b">", b")", b"}", b"]"):
            break
        position = end
    return position


def append_span(spans, start, end):
    # Coalesce adjacent escapes so large encoded assets do not need a tuple per byte.
    if spans and spans[-1][1] == start:
        spans[-1] = (spans[-1][0], end)
    else:
        spans.append((start, end))


def read_payload(data, position, prefix, quote, allow_whitespace):
    encoded = bytearray()
    spans = []
    while position < len(data):
        run = BODY_RUN.match(data, position)
        if run:
            encoded.extend(run[0])
            append_span(spans, position, run.end())
            position = run.end()
            continue
        joined = literal_join(data, position, prefix, quote)
        if joined:
            position, quote = joined
            allow_whitespace = True
            continue
        value, end = read_unit(data, position)
        if value and value[0] in WHITESPACE:
            if not allow_whitespace:
                break
            if data[position] in WHITESPACE:
                end = skip_layout(data, position, prefix)
                if end is None:
                    return None
        elif not value:
            if prefix and data[end:end + 1] == prefix:
                end += 1
        elif value in (b'"', b"'", b"`") and (not quote or value == quote):
            # HTML character references are content, not attribute delimiters.
            if data[position:position + 1] == b"&":
                return None
            break
        elif value == b"#":
            position = url_end(data, position, prefix, quote)
            break  # URL fragments are outside the Base64 body.
        elif not quote and value in (b"<", b">", b")", b"}", b"]"):
            break
        elif value[0] in b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/=%":
            encoded.extend(value)
            append_span(spans, position, end)
        else:
            return None
        position = end
    else:
        if quote:
            return None
    # Percent decoding follows source decoding, including escaped percent signs.
    encoded = unquote_to_bytes(bytes(encoded)).translate(None, WHITESPACE)
    if not encoded or not valid_base64(encoded):
        return None
    return spans, encoded, position


def filter_diff(data):
    output = []
    copied = 0
    position = 0
    while match := START.search(data, position):
        start = match.start()
        position = match.end()
        line_start = data.rfind(b"\n", 0, start) + 1
        prefix = data[line_start:line_start + 1]
        if prefix not in (b"+", b"-", b" "):
            prefix = b""
        quote = data[start - 1:start] if start and data[start - 1] in QUOTES else b""
        header = read_header(data, match.end(), prefix, quote)
        if not header:
            continue
        body_start, quote = header
        payload = read_payload(data, body_start, prefix, quote,
                               bool(quote) or start == line_start + len(prefix))
        if not payload:
            position = url_end(data, body_start, prefix, quote)
            continue
        spans, encoded, position = payload
        fingerprint = hashlib.sha256(encoded).hexdigest()
        placeholder = (
            f"[Base64 payload omitted: {len(encoded)} encoded bytes; sha256={fingerprint}]"
        ).encode("ascii")
        for begin, end in spans:
            output.extend((data[copied:begin], placeholder))
            placeholder = b""
            copied = end
    output.append(data[copied:])
    return b"".join(output)


if __name__ == "__main__":
    sys.stdout.buffer.write(filter_diff(sys.stdin.buffer.read()))
