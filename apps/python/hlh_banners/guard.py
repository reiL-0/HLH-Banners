# Request filter for the local port (Python 3.3 compatible: AC's own interpreter).
# A web page in the driver's browser can call 127.0.0.1; these rules make that useless:
# exact Host, no browser headers, a custom header (forces a preflight, and OPTIONS is refused), bounded body.

MAX_BODY = 1024 * 1024


def check(method, headers, port):
    """None when the request may be served, else (status, reason). `headers` is a dict-like of the request."""
    h = dict((k.lower(), v) for k, v in headers.items())
    if method != "POST":
        return (403 if method == "OPTIONS" else 405), "method"
    if h.get("host") != "127.0.0.1:%d" % port:
        return 403, "host"
    for k in h:
        if k in ("origin", "referer") or k.startswith("sec-fetch-"):
            return 403, "browser"
    if "transfer-encoding" in h:
        return 400, "chunked"
    if h.get("x-hlh-init") != "1":
        return 403, "header"
    try:
        n = int(h.get("content-length", ""))
    except ValueError:
        return 411, "length"
    if n < 0 or n > MAX_BODY:
        return 413, "size"
    return None
