"""Run every mock scenario twice and compare normalized transcripts."""

import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import time

from sfun_mock_endpoint import SCENARIOS, exact, frame


INPUT = bytes.fromhex(
    "feff3412dcfeeb32a4f8efcdab8900000080a50000000000f87f000000000000f03f"
)
OUTPUT = bytes.fromhex("0180cdabfeffffff98badcfe0000008001000000a50000000000f87f")
HASH = 0x12345678


def free_port():
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def client(port, scenario, process):
    deadline = time.monotonic() + 5
    while True:
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            raise AssertionError(f"endpoint exited early: {stdout}{stderr}")
        try:
            connection = socket.create_connection(("127.0.0.1", port), timeout=0.1)
            break
        except OSError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.01)
    with connection:
        connection.settimeout(0.35)
        connection.sendall(frame(1, struct.pack("<HI", 1, HASH)))
        assert exact(connection, 6) == frame(5, struct.pack("<H", 0))
        steps = 2 if scenario == "success" else 1
        for step in range(steps):
            connection.sendall(frame(2, struct.pack("<I", step) + INPUT))
            try:
                header = exact(connection, 4)
                if len(header) == 4:
                    _, length = struct.unpack("<HH", header)
                    exact(connection, length)
            except (OSError, TimeoutError):
                pass
        if scenario == "success":
            connection.sendall(frame(4))


def one_run(folder, scenario, repeat):
    port = free_port()
    transcript = os.path.join(folder, f"{scenario}_{repeat}.json")
    endpoint = os.path.join(os.path.dirname(__file__), "sfun_mock_endpoint.py")
    command = [sys.executable, endpoint, "--port", str(port),
               "--protocol-version", "1", "--interface-hash", hex(HASH),
               "--input-hex", INPUT.hex(), "--output-hex", OUTPUT.hex(),
               "--scenario", scenario, "--steps", "2" if scenario == "success" else "1",
               "--timeout-seconds", "0.3", "--transcript", transcript]
    process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    client(port, scenario, process)
    if process.wait(timeout=5):
        stdout, stderr = process.communicate()
        raise AssertionError(f"endpoint failed: {scenario}: {stdout}{stderr}")
    with open(transcript, encoding="utf-8") as stream:
        return json.load(stream)


def main():
    with tempfile.TemporaryDirectory() as folder:
        passed = 0
        for scenario in SCENARIOS:
            first = one_run(folder, scenario, 1)
            second = one_run(folder, scenario, 2)
            if first != second:
                raise AssertionError(f"non-repeatable transcript: {scenario}")
            print(json.dumps(first, sort_keys=True, separators=(",", ":")))
            passed += 1
    print(f"MOCK_REPEATABILITY=PASS scenarios={passed} repeats=2")
    print("FIELD_DECODE_FAILURE_HOST_INJECTION=NETWORK_OUTPUT_VALID_TEST_HARNESS_REQUIRED")


if __name__ == "__main__":
    main()
