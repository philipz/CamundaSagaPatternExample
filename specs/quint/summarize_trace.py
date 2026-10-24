#!/usr/bin/env python3
"""Turn a bookHoliday ITF trace into a compact Markdown step table.

Usage: summarize_trace.py <trace.itf.json> [title]
Columns: step | event | phase | process status/ref (F,T,H) | supplier active (F,T,H) | open tasks
"""
import json
import sys

ITEMS = ["Flight", "Train", "Hotel"]
ABBR = {"Flight": "F", "Train": "T", "Hotel": "H"}
STATUS = {"NoBooking": "–", "Confirmed": "Conf", "Canceled": "Canc"}


def val(v):
    """Decode ITF value into plain Python."""
    if isinstance(v, dict):
        if "#bigint" in v:
            return int(v["#bigint"])
        if "#set" in v:
            return sorted((val(x) for x in v["#set"]), key=str)
        if "#map" in v:
            return {key(k): val(x) for k, x in v["#map"]}
        if "#tup" in v:
            return tuple(val(x) for x in v["#tup"])
        if "tag" in v:
            inner = val(v["value"])
            return v["tag"] if inner == () else (v["tag"], inner)
        return {k: val(x) for k, x in v.items()}
    return v


def key(k):
    k = val(k)
    return fmt(k) if isinstance(k, tuple) else k


def fmt(x):
    if isinstance(x, tuple) and len(x) == 2 and isinstance(x[0], str):
        return f"{x[0]}({fmt(x[1])})"
    if isinstance(x, list):
        return "{" + ",".join(map(str, x)) + "}"
    return str(x)


def main():
    path = sys.argv[1]
    title = sys.argv[2] if len(sys.argv) > 2 else path
    d = json.load(open(path))
    rows = []
    for i, st in enumerate(d["states"]):
        s = {k.split("::")[-1]: val(v) for k, v in st.items() if k != "#meta"}
        e, sup, ts = s["engine"], s["supplier"], s["tasks"]
        if i == 0:
            need = [ABBR[x] for x in ITEMS if e["need"][x]]
            down = [ABBR[x] for x in ITEMS if sup["down"][x]]
            cdown = [ABBR[x] for x in ITEMS if sup["cancelDown"][x]]
            print(f"**{title}**  \nneed={'+'.join(need)}"
                  f"{'; supplier down=' + '+'.join(down) if down else ''}"
                  f"{'; cancel refused=' + '+'.join(cdown) if cdown else ''}\n")
        proc = " ".join(f"{ABBR[x]}:{STATUS[e['status'][x]]}/{e['ref'][x]}" for x in ITEMS)
        act = " ".join(f"{ABBR[x]}:{fmt(sup['active'][x])}" for x in ITEMS)
        open_tasks = []
        for k, t in ts.items():
            if t == "Absent":
                continue
            if isinstance(t, tuple):  # Locked(info)
                open_tasks.append(f"{k}🔒{'✔' if t[1]['sideEffectDone'] else ''}")
            else:
                open_tasks.append(k)
        rows.append((i, fmt(s["lastEvent"]), e["phase"], proc, act, ", ".join(sorted(open_tasks)) or "–"))
    print("| # | event | phase | process status/ref | supplier active | open tasks |")
    print("|---|---|---|---|---|---|")
    for r in rows:
        print("| " + " | ".join(map(str, r)) + " |")


if __name__ == "__main__":
    main()
