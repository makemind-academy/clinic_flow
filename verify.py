#!/usr/bin/env python3
"""clinic-flow: a routine with no judgement tool anywhere; readings carry their reference; marking a step done moves the next one up."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
from appplayer import AppPlayer  # noqa: E402
from mcpclient import Server  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "clinic_server")
CAP = os.path.join(HERE, "captures")
SERVER_ID = "com.makemind.sample.clinic"

WORDS = ["diagnos", "assess", "judg", "risk", "abnormal", "recommend"]
with Server(["dart", "run", "bin/server.dart"], cwd=SERVER) as s:
    for n in s.tool_names():
        assert not any(w in n.lower() for w in WORDS), n
    flow = s.call("flow.state")
    assert flow["stepCount"] == 6
    readings = s.call("readings.list")["readings"]
    assert len(readings) == 3 and all(r["usual"] for r in readings)

ap = AppPlayer()
ap.register_server(SERVER_ID, "Clinic routine", cwd=SERVER)
ap.restart()
ap.open_server(SERVER_ID)
ap.wait_text("Examination")
ap.wait_text("Mark this step done")
ap.wait_text("/ 6")
ap.shot(f"{CAP}/01_routine.png")
ap.tap("Mark this step done")
ap.wait_text("2 / 6")
ap.expect_text("bp")                 # the next step names the readings it needs first
ap.shot(f"{CAP}/02_step_done.png")
ap.tap("Readings →")
ap.wait_text("36.1-37.2")               # the last of the three readings is on screen
ap.expect_aligned("usual", min_rows=3, edge="left")   # the label is left-aligned in its own column
ap.expect_aligned("-", min_rows=2)                    # the ranges are right-aligned
ap.shot(f"{CAP}/03_readings.png")
print("clinic-flow: six steps, three done on screen, readings with their reference, no judgement tool")
