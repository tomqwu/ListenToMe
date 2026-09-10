#!/usr/bin/env python3
"""Kill an isolated synthetic archive writer after an acknowledged checkpoint, then reopen it.

Uses the production SessionArchive source. Never reads or writes application/user history.
This validates the persistence boundary, not GUI save timers, audio capture, or power-loss durability.
"""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="listentome-recovery-") as temp:
    root = Path(temp)
    source = root / "main.swift"
    source.write_text('''import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[2])
let archive = SessionArchive(directory: directory)
if CommandLine.arguments[1] == "write" {
    let segment = TranscriptSegment(source: .others, text: "Alice ships Wednesday", isFinal: true,
                                    start: 0, end: 5, speakerID: "alice", speakerName: "Alice")
    let record = SessionRecord(id: "synthetic-A", title: "Recovery fixture", date: Date(),
        transcript: segment.text, summary: "", segments: [segment], notes: "Synthetic only", isComplete: false)
    try archive.save(record)
    FileHandle.standardOutput.write(Data("ACK\\n".utf8))
    while true { Thread.sleep(forTimeInterval: 1) }
} else {
    let records = try archive.all()
    precondition(records.count == 1)
    precondition(records[0].transcript == "Alice ships Wednesday")
    precondition(records[0].notes == "Synthetic only")
    precondition(records[0].segments?[0].speakerName == "Alice")
    precondition(records[0].isComplete == false)
    print("PASS: acknowledged transcript, notes, and speaker identity recovered after SIGKILL")
}
''')
    binary = root / "recovery"
    core = repo / "Sources/ListenToMeCore"
    subprocess.run(["swiftc", str(core / "Models.swift"), str(core / "SessionSearch.swift"),
                    str(core / "SessionArchive.swift"), str(source), "-o", str(binary)], check=True)
    directory = root / "archive"
    writer = subprocess.Popen([str(binary), "write", str(directory)], stdout=subprocess.PIPE, text=True)
    try:
        assert writer.stdout.readline().strip() == "ACK", "write was not acknowledged"
    finally:
        writer.kill()
        writer.wait(timeout=5)
    subprocess.run([str(binary), "read", str(directory)], check=True)
