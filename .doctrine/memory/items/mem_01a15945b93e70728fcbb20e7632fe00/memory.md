`doctrine review show RV-NNN -f F-n` prints every turn verbatim (raise/dispose/contest/
amend) and runs to hundreds of lines per finding. For the *current* response and route
when transcribing into plan criteria, read the ledger directly:

    python3 - <<PL
    import tomllib, pathlib
    d = tomllib.loads(pathlib.Path(".doctrine/review/046/review-046.toml").read_text())
    for f in d["finding"]:
        if f.get("route") != "demonstrate": continue
        print(f["id"], f["severity"], f["status"], "|", f["title"])
        print("RESPONSE:", (f.get("response") or "")[:2600])
    PL

`route` sits on the finding; `turns[]` holds the history.