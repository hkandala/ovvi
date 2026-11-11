#!/usr/bin/env python3
"""`cargo build --release` for the welcome's first clip (scripts/record-onboarding.sh): a real build's output (a
small axum service's crates, in the order cargo built them), replayed at its pace in a few seconds, with cargo's
colors and its progress bar under the lines. Nothing compiles: the scene has no crates and no network."""
import os
import random
import shutil
import sys
import time

CRATES = """proc-macro2 1.0.92, unicode-ident 1.0.14, libc 0.2.168, cfg-if 1.0.0, autocfg 1.4.0, once_cell 1.20.2,
pin-project-lite 0.2.15, bytes 1.9.0, itoa 1.0.14, smallvec 1.13.2, memchr 2.7.4, serde 1.0.216, quote 1.0.37,
log 0.4.22, futures-core 0.3.31, scopeguard 1.2.0, lock_api 0.4.12, parking_lot_core 0.9.10, syn 2.0.90,
version_check 0.9.5, typenum 1.17.0, generic-array 0.14.7, tracing-core 0.1.33, futures-sink 0.3.31, fnv 1.0.7,
http 1.2.0, slab 0.4.9, futures-task 0.3.31, pin-utils 0.1.0, socket2 0.5.8, mio 1.0.3, parking_lot 0.12.3,
signal-hook-registry 1.4.2, ryu 1.0.18, percent-encoding 2.3.1, tokio-macros 2.4.0, serde_derive 1.0.216,
tracing-attributes 0.1.28, futures-util 0.3.31, tokio 1.42.0, tracing 0.1.41, http-body 1.0.1, httparse 1.9.5,
form_urlencoded 1.2.1, crypto-common 0.1.6, block-buffer 0.10.4, digest 0.10.7, cpufeatures 0.2.16, sha2 0.10.8,
tower-service 0.3.3, tower-layer 0.3.3, httpdate 1.0.3, atomic-waker 1.1.2, try-lock 0.2.5, want 0.3.1,
http-body-util 0.1.2, mime 0.3.17, sync_wrapper 1.0.2, rustversion 1.0.18, async-trait 0.1.83, hyper 1.5.1,
serde_json 1.0.133, serde_urlencoded 0.7.1, matchit 0.7.3, axum-core 0.4.5, hyper-util 0.1.10, tower 0.5.2,
getrandom 0.2.15, rand_core 0.6.4, ppv-lite86 0.2.20, rand_chacha 0.3.1, rand 0.8.5, base64 0.22.1,
thiserror-impl 2.0.6, thiserror 2.0.6, time-core 0.1.2, num-conv 0.1.0, powerfmt 0.2.0, deranged 0.3.11,
time 0.3.37, sharded-slab 0.1.7, thread_local 1.1.8, nu-ansi-term 0.46.0, tracing-log 0.2.0,
tracing-subscriber 0.3.19, url 2.5.4, axum 0.7.9, tower-http 0.6.2, dashmap 6.1.0, nanoid 0.4.0, dotenvy 0.15.7"""
GREEN, CYAN, OFF = "\x1b[1m\x1b[32m", "\x1b[1m\x1b[36m", "\x1b[0m"


def main():
    if sys.argv[1:2] != ["build"]:
        sys.exit(f"{GREEN}error{OFF}: this cargo only builds")
    crates = [crate.strip().split() for crate in CRATES.split(",")]
    root = os.getcwd().replace(os.path.expanduser("~"), "/Users/alex")
    name = os.path.basename(os.getcwd())
    crates.append([name, "0.4.0", f"({root})"])
    pace = float(os.environ.get("OVVI_CARGO_SECONDS", "3")) / len(crates)
    width = shutil.get_terminal_size().columns
    building = []
    shown = random.Random(7)

    def bar(done):
        room = max(10, min(40, width - 40))
        fill = room * done // len(crates)
        text = f"[{'=' * max(0, fill - 1)}{'>' if fill else ''}{' ' * (room - fill)}] {done}/{len(crates)}: "
        names = building[:]
        while len(names) > 1 and 13 + len(text + ", ".join(names)) >= width:
            names.pop(0)
        # Never wider than the terminal: a wrapped bar would stay above the next line.
        return f"\r\x1b[K{CYAN}    Building{OFF} " + (text + ", ".join(names))[:width - 14]

    for done, crate in enumerate(crates):
        building = (building + [crate[0]])[-4:]
        line = f"{GREEN}   Compiling{OFF} {crate[0]} v{crate[1]}" + (f" {crate[2]}" if len(crate) > 2 else "")
        sys.stdout.write("\r\x1b[K" + line + "\n" + bar(done))
        sys.stdout.flush()
        # Small crates come in bursts; the big ones (and the service itself) take their time.
        big = crate[0] in {"syn", "tokio", "hyper", "serde_derive", "axum", "tower-http", name}
        time.sleep(pace * (4 if big else shown.uniform(0.3, 1.4)))
    time.sleep(0.5)
    # Cargo's words before 1.77: today's add "`release` profile" and wrap in the clip's pane.
    sys.stdout.write(f"\r\x1b[K{GREEN}    Finished{OFF} release [optimized] target(s) in 38.42s\n")


main()
