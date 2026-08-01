"""Deterministic single-session DSP-SimBridge mock endpoint."""

import argparse
import json
import socket
import struct
import sys
import time


SCENARIOS = (
    "success", "response_error", "response_zero", "wrong_type",
    "short_length", "long_length", "odd_length", "wrong_step",
    "header_truncated", "payload_truncated", "timeout", "disconnect",
    "field_decode_failure",
)


def frame(message_type, payload=b""):
    return struct.pack("<HH", message_type, len(payload)) + payload


def exact(connection, size):
    data = bytearray()
    while len(data) < size:
        part = connection.recv(size - len(data))
        if not part:
            break
        data.extend(part)
    return bytes(data)


def parse_args(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--protocol-version", type=int, required=True)
    parser.add_argument("--interface-hash", type=lambda value: int(value, 0), required=True)
    parser.add_argument("--input-hex", required=True)
    parser.add_argument("--output-hex", required=True)
    parser.add_argument("--scenario", choices=SCENARIOS, required=True)
    parser.add_argument("--steps", type=int, default=1)
    parser.add_argument("--timeout-seconds", type=float, default=1.0)
    parser.add_argument("--transcript", required=True)
    parser.add_argument("--ready-file")
    return parser.parse_args(argv)


def send_reply(connection, scenario, step, output_bytes, timeout_seconds):
    payload = struct.pack("<I", step) + output_bytes
    if scenario in ("success", "field_decode_failure"):
        connection.sendall(frame(3, payload))
    elif scenario == "response_error":
        connection.sendall(frame(5, struct.pack("<H", 7)))
    elif scenario == "response_zero":
        connection.sendall(frame(5, struct.pack("<H", 0)))
    elif scenario == "wrong_type":
        connection.sendall(frame(4))
    elif scenario == "short_length":
        connection.sendall(frame(3, payload[:-2]))
    elif scenario == "long_length":
        connection.sendall(struct.pack("<HH", 3, len(payload) + 2))
    elif scenario == "odd_length":
        connection.sendall(struct.pack("<HH", 3, len(payload) - 1))
    elif scenario == "wrong_step":
        connection.sendall(frame(3, struct.pack("<I", step + 1) + output_bytes))
    elif scenario == "header_truncated":
        connection.sendall(b"\x03\x00")
        connection.shutdown(socket.SHUT_WR)
    elif scenario == "payload_truncated":
        connection.sendall(struct.pack("<HH", 3, len(payload)) + payload[:8])
        connection.shutdown(socket.SHUT_WR)
    elif scenario == "timeout":
        time.sleep(min(timeout_seconds * 1.5, 1.5))
    elif scenario == "disconnect":
        connection.shutdown(socket.SHUT_RDWR)


def run(options):
    inputs = bytes.fromhex(options.input_hex)
    outputs = bytes.fromhex(options.output_hex)
    transcript = {
        "scenario": options.scenario,
        "accepted_connection_count": 0,
        "sim_start_hex": "",
        "input_data_hex": [],
        "input_steps": [],
        "reply_type": [],
        "reply_length": [],
        "reply_step": [],
        "sim_stop_observed": False,
        "connection_closed": False,
        "extra_reconnect_count": 0,
        "result": "FAIL",
    }
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", options.port))
    listener.listen(2)
    listener.settimeout(options.timeout_seconds)
    if options.ready_file:
        with open(options.ready_file, "w", encoding="ascii", newline="\n") as stream:
            stream.write("READY\n")
    failure = ""
    try:
        connection, _ = listener.accept()
        transcript["accepted_connection_count"] = 1
        connection.settimeout(options.timeout_seconds)
        with connection:
            start = exact(connection, 10)
            transcript["sim_start_hex"] = start.hex()
            expected_start = frame(1, struct.pack(
                "<HI", options.protocol_version, options.interface_hash))
            if start != expected_start:
                raise AssertionError("SIM_START mismatch")
            connection.sendall(frame(5, struct.pack("<H", 0)))
            for expected_step in range(options.steps):
                header = exact(connection, 4)
                if len(header) != 4:
                    raise AssertionError("INPUT_DATA header missing")
                message_type, length = struct.unpack("<HH", header)
                payload = exact(connection, length)
                transcript["input_data_hex"].append((header + payload).hex())
                if message_type != 2 or payload != struct.pack("<I", expected_step) + inputs:
                    raise AssertionError("INPUT_DATA mismatch")
                transcript["input_steps"].append(expected_step)
                active = "success" if expected_step + 1 < options.steps else options.scenario
                if active in ("response_error", "response_zero"):
                    reply_type, reply_length, reply_step = 5, 2, None
                elif active == "wrong_type":
                    reply_type, reply_length, reply_step = 4, 0, None
                elif active == "header_truncated":
                    reply_type, reply_length, reply_step = None, None, None
                elif active == "long_length":
                    reply_type, reply_length, reply_step = 3, len(outputs) + 6, None
                elif active == "odd_length":
                    reply_type, reply_length, reply_step = 3, len(outputs) + 3, None
                else:
                    reply_type = 3 if active not in ("timeout", "disconnect") else None
                    reply_length = len(outputs) + 4 if reply_type else None
                    reply_step = expected_step + (active == "wrong_step") if reply_type else None
                transcript["reply_type"].append(reply_type)
                transcript["reply_length"].append(reply_length)
                transcript["reply_step"].append(reply_step)
                send_reply(connection, active, expected_step, outputs, options.timeout_seconds)
                if active != "success":
                    break
            if options.scenario == "success":
                transcript["sim_stop_observed"] = exact(connection, 4) == frame(4)
                if not transcript["sim_stop_observed"]:
                    raise AssertionError("SIM_STOP missing")
            try:
                transcript["connection_closed"] = connection.recv(1) == b""
            except (ConnectionError, OSError, TimeoutError):
                transcript["connection_closed"] = options.scenario != "success"
        listener.settimeout(0.2)
        try:
            extra, _ = listener.accept()
            transcript["extra_reconnect_count"] += 1
            extra.close()
        except TimeoutError:
            pass
        if transcript["accepted_connection_count"] == 1 and not transcript["extra_reconnect_count"]:
            transcript["result"] = "PASS"
    except Exception as error:  # transcript is the diagnostic boundary
        failure = str(error)
        transcript["failure"] = failure
    finally:
        listener.close()
        with open(options.transcript, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(transcript, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
    return 0 if transcript["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(run(parse_args()))
