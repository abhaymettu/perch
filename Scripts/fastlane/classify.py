#!/usr/bin/env python3
"""classify.py -- fast-lane intent classifier for the Jarvis device lane.

One utterance in, one JSON object out: an intent from the fixed device-verb
table (see INTENTS below) plus the exact daemon op to send, or FALLBACK when
the utterance isn't an unambiguous, in-range, single device command. Tier 1 is
whole-utterance regex (cheap, zero false-fires by construction). Tier 2 is a
small local model behind any OpenAI-compatible chat endpoint, used only when
tier 1 doesn't match at all. Model output is data: it is parsed and validated
against the same intent table and slot rules as tier 1, never executed or
shell-interpolated. See docs/fastlane/SPEC.md FR-B and docs/fastlane/PLAN.md
decisions 5-6.

Python 3.9+ stdlib only (targets 3.9: no match, no X | Y unions -- the daemon
shells to this with /usr/bin/python3).

CLI:
    classify.py [--json] [--mode hybrid|rules|llm] [--url URL] [--model MODEL] "<text>"

Prints exactly one JSON line and exits 0 whenever a JSON result was produced,
including ok:false on LLM errors. Exits 2 on a usage error (argparse default).

Env:
    FASTLANE_LLM_URL    default http://127.0.0.1:10100/inference/v1/chat/completions
    FASTLANE_LLM_MODEL  default gemma-4-e2b-it-qat:gguf:q4
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request

DEFAULT_URL = "http://127.0.0.1:10100/inference/v1/chat/completions"
DEFAULT_MODEL = "gemma-4-e2b-it-qat:gguf:q4"

# ---------------------------------------------------------------------------
# app name resolution -- same alias map as ~/code/local-workers/interp.py,
# copied rather than imported so this file is portable to the cloud sandbox
# (no /Applications there, so aliases are all it has).
# ---------------------------------------------------------------------------

ALIASES = {
    "chrome": "Google Chrome", "google chrome": "Google Chrome", "safari": "Safari",
    "music": "Music", "apple music": "Music", "notes": "Notes", "spotify": "Spotify",
    "slack": "Slack", "code": "Visual Studio Code", "vscode": "Visual Studio Code",
    "vs code": "Visual Studio Code", "cursor": "Cursor", "terminal": "Terminal",
    "iterm": "iTerm", "ghostty": "Ghostty", "warp": "Warp", "finder": "Finder",
    "mail": "Mail", "messages": "Messages", "calendar": "Calendar",
    "reminders": "Reminders", "preview": "Preview", "pages": "Pages",
    "numbers": "Numbers", "keynote": "Keynote", "arc": "Arc", "firefox": "Firefox",
    "zoom": "zoom.us", "discord": "Discord", "notion": "Notion", "obsidian": "Obsidian",
    "figma": "Figma", "linear": "Linear", "excel": "Microsoft Excel",
    "word": "Microsoft Word", "powerpoint": "Microsoft PowerPoint", "photos": "Photos",
    "maps": "Maps", "settings": "System Settings", "system settings": "System Settings",
    "system preferences": "System Settings", "activity monitor": "Activity Monitor",
    "calculator": "Calculator", "textedit": "TextEdit", "freeform": "Freeform",
    "facetime": "FaceTime", "app store": "App Store", "books": "Books",
    "podcasts": "Podcasts", "tv": "TV", "news": "News", "stocks": "Stocks",
    "weather": "Weather", "clock": "Clock", "home": "Home", "shortcuts": "Shortcuts",
    "xcode": "Xcode", "simulator": "Simulator", "docker": "Docker",
    "postman": "Postman", "tableplus": "TablePlus", "raycast": "Raycast",
    "1password": "1Password", "whatsapp": "WhatsApp", "telegram": "Telegram",
    "signal": "Signal", "twitter": "Twitter", "x": "Twitter", "youtube": "Google Chrome",
}

_apps_cache = None


def _is_mac():
    return os.path.isdir("/Applications")


def _installed_apps():
    # Mac-only. On the cloud there is no /Applications, so callers must not
    # rely on this for app resolution there (see resolve_app).
    global _apps_cache
    if _apps_cache is not None:
        return _apps_cache
    names = set()
    home = os.path.expanduser("~")
    for d in ("/Applications", "/System/Applications", "/System/Applications/Utilities",
              os.path.join(home, "Applications")):
        try:
            for e in os.listdir(d):
                if e.endswith(".app"):
                    names.add(e[:-4])
        except OSError:
            pass
    _apps_cache = sorted(names, key=str.lower)
    return _apps_cache


def resolve_app(name):
    """Alias or exact installed name -> canonical app name daemon accepts, else None.

    Deliberately stricter than interp.py's resolve_app (no prefix/substring
    fuzzy matching): a false app match here is a false-fire on a device verb,
    and the adversarial test set specifically probes for that ("raise my
    salary", "open the window"). Exact match only.
    """
    if not isinstance(name, str):
        return None
    n = name.strip().strip('"').rstrip(".")
    if not n or len(n) > 64 or any(c in n for c in '"\\\n'):
        return None
    low = n.lower()
    if low in ALIASES:
        return ALIASES[low]
    if _is_mac():
        for a in _installed_apps():
            if a.lower() == low:
                return a
    return None


# ---------------------------------------------------------------------------
# value representation
#
# The daemon (instinct-daemon.lua, pct(), D1) reads `value` as a fraction when
# <= 1 and as a 0..100 percentage otherwise: 1 means 100%. That makes the
# integer 1 alone ambiguous -- it would land as 100%, not 1%. Decision: send
# plain integers 2..100 (unambiguous, > 1) and 0 (unambiguous either way), and
# for the single ambiguous case, value == 1, send the fraction 0.01 instead
# (0.01 <= 1, so the daemon multiplies by 100 and gets 1). Every other value
# never touches the <=1 branch.
# ---------------------------------------------------------------------------

def to_daemon_value(n):
    if n == 1:
        return 0.01
    return n


_WORDS = {"zero": 0, "max": 100, "full": 100, "hundred": 100, "half": 50}


def word_to_num(tok):
    tok = tok.strip().lower()
    if tok in _WORDS:
        return _WORDS[tok]
    if tok.isdigit():
        n = int(tok)
        if 0 <= n <= 100:
            return n
    return None


# ---------------------------------------------------------------------------
# tier 1: whole-utterance regex rules
# ---------------------------------------------------------------------------

_FILLER_RES = [
    re.compile(r"^hey jarvis[,\s]+"),
    re.compile(r"^jarvis[,\s]+"),
    re.compile(r"^hey[,\s]+"),
    re.compile(r"^please\s+"),
    re.compile(r"^can you\s+"),
    re.compile(r"^could you\s+"),
    re.compile(r"^would you\s+"),
]


def normalize(text):
    """Lowercase, strip leading filler ('please', 'hey jarvis', 'can you', ...),
    trailing 'please' and punctuation, and collapse whitespace, so tier 1's
    regexes only have to know the bare command."""
    s = text.strip().lower()
    s = s.replace("’", "'")
    changed = True
    while changed:
        changed = False
        for pat in _FILLER_RES:
            new = pat.sub("", s)
            if new != s:
                s, changed = new, True
    s = re.sub(r"\s+please\s*$", "", s)
    s = re.sub(r"[.!?]+$", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


NUM = r"(zero|max|full|hundred|half|\d{1,3})\s*(?:%|percent)?"

BRIGHTNESS_SET_RE = re.compile(r"^(?:set )?(?:the )?brightness(?: to)? " + NUM + r"$")
BRIGHTNESS_GET_RE = re.compile(r"^what(?:'s| is) my brightness\??$")
VOLUME_SET_RE = re.compile(r"^(?:set |turn )?(?:the )?volume(?: to)? " + NUM + r"$")
VOLUME_GET_RE = re.compile(r"^what(?:'s| is) my volume\??$")
MUTE_RE = re.compile(r"^mute$")
UNMUTE_RE = re.compile(r"^unmute$")
LOCK_RE = re.compile(r"^lock (?:the )?screen$|^lock my mac$")
FRONTMOST_RE = re.compile(r"^what app is (?:open|frontmost)\??$")
OPEN_RE = re.compile(r"^open (.+)$")
SWITCH_RE = re.compile(r"^switch to (.+)$")
RAISE_RE = re.compile(r"^raise (.+)$")
HIDE_RE = re.compile(r"^hide (.+)$")
FULLSCREEN_RE = re.compile(r"^fullscreen (.+)$")
MINIMIZE_RE = re.compile(r"^minimize (.+)$")
URL_SCHEME_RE = re.compile(r"^https?://\S+$")

LOCK_OP = {"action": "key.press", "key": "q", "mods": ["cmd", "ctrl"]}

# Generic near-miss guards, tried only after every exact positive pattern has
# failed to match. Each catches a whole class of "shares vocabulary with a
# device verb but isn't one" utterances deterministically, so the LLM tier
# never has to be trusted with them (PLAN decision 5: rules first, model
# only sees what rules didn't already resolve).
NEGATION_RE = re.compile(r"^(?:don'?t|do not|never)\b")
QUESTION_RE = re.compile(r"^(?:what|how|why|who|when|is|are|do|does|did)\b")
RELATIVE_WORDS_RE = re.compile(r"\b(?:louder|quieter|brighter|dimmer)\b")
MUTE_PREFIX_RE = re.compile(r"^(?:un)?mute\s+\S")
LOCK_PREFIX_RE = re.compile(r"^lock\s+\S")
BRIGHTNESS_PREFIX_RE = re.compile(r"^(?:set\s+)?(?:the\s+)?brightness\b")
VOLUME_PREFIX_RE = re.compile(r"^(?:set\s+|turn\s+)?(?:the\s+)?volume\b")


def tier1(text):
    """Returns (status, op, intent). status is one of:
      "op"       -- matched and valid; op is the daemon op, intent is set.
      "fallback" -- matched the pattern for a known verb but a slot failed
                    validation (bad number, unresolvable app); this is
                    decided here, definitively, without going to the LLM.
      "none"     -- no pattern matched at all; caller may try the LLM tier.
    """
    core = normalize(text)

    if NEGATION_RE.match(core):
        return "fallback", None, None

    m = BRIGHTNESS_SET_RE.match(core)
    if m:
        n = word_to_num(m.group(1))
        if n is None:
            return "fallback", None, "brightness.set"
        return "op", {"action": "brightness.set", "value": to_daemon_value(n)}, "brightness.set"

    if BRIGHTNESS_GET_RE.match(core):
        return "op", {"action": "brightness.get"}, "brightness.get"

    if BRIGHTNESS_PREFIX_RE.match(core):
        # starts with "brightness" but isn't a valid 0..100 value command
        # ("brightness off", "brightness of the future", "brightness up a bit")
        return "fallback", None, "brightness.set"

    m = VOLUME_SET_RE.match(core)
    if m:
        n = word_to_num(m.group(1))
        if n is None:
            return "fallback", None, "volume.set"
        return "op", {"action": "volume.set", "value": to_daemon_value(n)}, "volume.set"

    if VOLUME_GET_RE.match(core):
        return "op", {"action": "volume.get"}, "volume.get"

    if VOLUME_PREFIX_RE.match(core):
        # starts with "volume" but isn't a valid 0..100 value command
        return "fallback", None, "volume.set"

    if MUTE_RE.match(core):
        return "op", {"action": "mute.set", "value": True}, "mute.set"

    if UNMUTE_RE.match(core):
        return "op", {"action": "mute.set", "value": False}, "mute.set"

    if MUTE_PREFIX_RE.match(core):
        # mute/unmute take no object; "mute X" for any X is not our verb
        # ("mute the guy in the meeting", "mute after the call", "mute and
        # lock the screen")
        return "fallback", None, "mute.set"

    if LOCK_RE.match(core):
        return "op", dict(LOCK_OP), "lock_screen"

    if LOCK_PREFIX_RE.match(core):
        # "lock X" where X isn't the screen or the mac ("lock the door")
        return "fallback", None, "lock_screen"

    if RELATIVE_WORDS_RE.search(core):
        # comparative audio/brightness words never carry an absolute value
        return "fallback", None, None

    if FRONTMOST_RE.match(core):
        return "op", {"action": "app.frontmost"}, "app.frontmost"

    m = FULLSCREEN_RE.match(core)
    if m:
        app = resolve_app(m.group(1))
        if not app:
            return "fallback", None, "window.fullscreen"
        return "op", {"action": "window.fullscreen", "app": app, "value": True}, "window.fullscreen"

    m = MINIMIZE_RE.match(core)
    if m:
        app = resolve_app(m.group(1))
        if not app:
            return "fallback", None, "window.minimize"
        return "op", {"action": "window.minimize", "app": app}, "window.minimize"

    m = HIDE_RE.match(core)
    if m:
        app = resolve_app(m.group(1))
        if not app:
            return "fallback", None, "app.hide"
        return "op", {"action": "app.hide", "app": app}, "app.hide"

    m = SWITCH_RE.match(core) or RAISE_RE.match(core)
    if m:
        app = resolve_app(m.group(1))
        if not app:
            return "fallback", None, "app.raise"
        return "op", {"action": "app.raise", "app": app}, "app.raise"

    m = OPEN_RE.match(core)
    if m:
        target = m.group(1).strip()
        if URL_SCHEME_RE.match(target):
            return "op", {"action": "url.open", "url": target}, "url.open"
        app = resolve_app(target)
        if app:
            return "op", {"action": "app.raise", "app": app}, "app.raise"
        # "open X" is an unambiguous verb+target; an unresolvable, non-url
        # target is a definitive fallback, not a rule non-match.
        return "fallback", None, "url.open"

    if resolve_app(core):
        # bare app name, no verb ("chrome") -- explicitly must-fallback per spec
        return "fallback", None, "app.raise"

    if QUESTION_RE.match(core):
        # a question, not an imperative ("what is brightness", "how do i lock
        # the screen") -- only reached once every real GET/frontmost pattern
        # above has already had its chance to match
        return "fallback", None, None

    return "none", None, None


# ---------------------------------------------------------------------------
# tier 2: small local model
# ---------------------------------------------------------------------------

INTENTS = (
    "brightness.set", "brightness.get", "volume.set", "volume.get", "mute.set",
    "app.raise", "app.hide", "window.fullscreen", "window.minimize", "url.open",
    "lock_screen", "app.frontmost",
)

SYSTEM_PROMPT = (
    "You map ONE Mac voice command to a device intent. Reply with exactly one "
    'JSON object: {"intent": NAME, "args": {...}}, nothing else.\n'
    "Intents: brightness.set{value:0-100} brightness.get{} volume.set{value:0-100} "
    "volume.get{} mute.set{value:bool} app.raise{app} app.hide{app} "
    "window.fullscreen{app,value:bool} window.minimize{app} url.open{url, http/https} "
    "lock_screen{} app.frontmost{}\n"
    "Answer FALLBACK for: a relative change (up, louder, a bit), a conditional or "
    "delayed command (after, in N minutes), a negation (don't, never), two actions "
    "in one command, a bare app name with no verb, a question (what, how, is), "
    "\"brightness off\" (brightness has no off state), or words that only sound "
    "like an intent but are about something else (a door, a salary, a person) -- "
    "these fall back even though they share vocabulary.\n"
    'Examples -> {"intent":"FALLBACK","args":{}}: "lock the door", "make it '
    'louder", "chrome", "mute and lock the screen", "how do i lock the screen".\n'
    "JSON only, no prose, no markdown."
)


def call_llm(text, url, model):
    body = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text},
        ],
        "temperature": 0,
        "max_tokens": 80,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            d = json.load(r)
    except Exception as e:
        return None, "llm request failed: " + str(e)
    try:
        msg = d["choices"][0]["message"]
        out = (msg.get("content") or msg.get("reasoning_content") or "").strip()
    except Exception as e:
        return None, "unexpected llm response shape: " + str(e)
    return out, None


def parse_llm_json(raw):
    """First {...} in the output -> (intent, args, error). Never eval/exec."""
    if not raw:
        return None, None, "empty model output"
    s = raw.strip()
    s = s.removeprefix("```json").removeprefix("```").removesuffix("```").strip()
    m = re.search(r"\{.*\}", s, re.S)
    if not m:
        return None, None, "no json object in model output"
    try:
        obj = json.loads(m.group(0))
    except Exception as e:
        return None, None, "invalid json: " + str(e)
    if not isinstance(obj, dict):
        return None, None, "model output is not a json object"
    intent = obj.get("intent")
    args = obj.get("args")
    if not isinstance(args, dict):
        args = {}
    if not isinstance(intent, str):
        return None, None, "missing intent field"
    return intent, args, None


def validate_op(intent, args):
    """Model output is data: intent must be in the table, slots must validate,
    else None (FALLBACK). Same rules tier 1 applies to its own matches."""
    if intent not in INTENTS:
        return None

    if intent in ("brightness.set", "volume.set"):
        v = args.get("value")
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            return None
        n = int(round(v))
        if n < 0 or n > 100 or abs(v - n) > 1e-6:
            return None
        return {"action": intent, "value": to_daemon_value(n)}

    if intent == "mute.set":
        v = args.get("value")
        if not isinstance(v, bool):
            return None
        return {"action": "mute.set", "value": v}

    if intent in ("app.raise", "app.hide", "window.minimize"):
        app = resolve_app(args.get("app"))
        if not app:
            return None
        return {"action": intent, "app": app}

    if intent == "window.fullscreen":
        app = resolve_app(args.get("app"))
        v = args.get("value")
        if not app or not isinstance(v, bool):
            return None
        return {"action": "window.fullscreen", "app": app, "value": v}

    if intent == "url.open":
        u = args.get("url")
        if not isinstance(u, str) or len(u) < 11 or len(u) > 300:
            return None
        if not re.match(r"^https?://[^\s'\"\\]+$", u):
            return None
        return {"action": "url.open", "url": u}

    if intent == "lock_screen":
        return dict(LOCK_OP)

    if intent == "brightness.get":
        return {"action": "brightness.get"}

    if intent == "volume.get":
        return {"action": "volume.get"}

    if intent == "app.frontmost":
        return {"action": "app.frontmost"}

    return None


# ---------------------------------------------------------------------------
# public entry point
# ---------------------------------------------------------------------------

def classify(text, mode="hybrid", url=None, model=None):
    t0 = time.monotonic()
    result = {
        "ok": True, "text": text, "intent": "FALLBACK", "op": None, "fallback": True,
        "tier": "none", "ms": 0.0, "model": None, "raw": None, "error": None,
    }
    if mode not in ("hybrid", "rules", "llm"):
        mode = "hybrid"

    if mode in ("hybrid", "rules"):
        status, op, intent = tier1(text)
        if status != "none":
            result["tier"] = "rules"
            if status == "op":
                result["intent"], result["op"], result["fallback"] = intent, op, False
            else:
                result["intent"] = intent or "FALLBACK"
            result["ms"] = (time.monotonic() - t0) * 1000.0
            return result
        if mode == "rules":
            result["ms"] = (time.monotonic() - t0) * 1000.0
            return result

    # llm tier: mode == "llm", or mode == "hybrid" with no rule match
    model = model or os.environ.get("FASTLANE_LLM_MODEL", DEFAULT_MODEL)
    url = url or os.environ.get("FASTLANE_LLM_URL", DEFAULT_URL)
    result["tier"] = "llm"
    result["model"] = model

    raw, err = call_llm(text, url, model)
    if err:
        result["ok"], result["error"] = False, err
        result["ms"] = (time.monotonic() - t0) * 1000.0
        return result

    result["raw"] = raw[:200]
    intent, args, perr = parse_llm_json(raw)
    if perr:
        result["ok"], result["error"] = False, perr
        result["ms"] = (time.monotonic() - t0) * 1000.0
        return result

    op = validate_op(intent, args)
    if op is None:
        result["intent"] = "FALLBACK"
    else:
        result["intent"], result["op"], result["fallback"] = intent, op, False
    result["ms"] = (time.monotonic() - t0) * 1000.0
    return result


def main():
    ap = argparse.ArgumentParser(description="Classify one utterance into a device op.")
    ap.add_argument("--json", action="store_true", help="present for CLI compatibility; output is always one JSON line")
    ap.add_argument("--mode", choices=["hybrid", "rules", "llm"], default="hybrid")
    ap.add_argument("--url")
    ap.add_argument("--model")
    ap.add_argument("text")
    args = ap.parse_args()

    result = classify(args.text, mode=args.mode, url=args.url, model=args.model)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
