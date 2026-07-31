import socket
import subprocess
import sys
import threading
import time


CLIENT, INSTANCE_DIR = sys.argv[1:3]


def run_server(handler, mode, timeout=8):
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    port = listener.getsockname()[1]
    failure = []

    def target():
        try:
            connection, _ = listener.accept()
            with connection:
                handler(connection)
        except Exception as exc:  # test helper reports this in the parent
            failure.append(exc)
        finally:
            listener.close()

    thread = threading.Thread(target=target, daemon=True)
    thread.start()
    result = subprocess.run(
        [CLIENT, "127.0.0.1", str(port), mode],
        cwd=INSTANCE_DIR, text=True, capture_output=True, timeout=timeout)
    thread.join(timeout=timeout)
    if thread.is_alive():
        raise AssertionError("mock server did not terminate")
    if failure:
        raise failure[0]
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout


def segmented(connection, pieces, delay=0.02):
    for piece in pieces:
        connection.sendall(piece)
        time.sleep(delay)


def expect(name, condition, detail=""):
    if not condition:
        raise AssertionError(f"{name}: {detail}")
    print(f"PASS {name}")


captured = bytearray()


def capture_golden(connection):
    while len(captured) < 20:
        part = connection.recv(64)
        if not part:
            break
        captured.extend(part)


out = run_server(capture_golden, "golden")
expected = bytes.fromhex(
    "01000600010078563412"  # SIM_START
    "04000000"              # SIM_STOP
    "02000200aabb")         # INPUT_DATA
expect("connect_success_and_golden_vectors", bytes(captured) == expected,
       captured.hex())
expect("golden_send_socket_remains_valid", "status=0 valid=1" in out, out)

out = run_server(lambda c: segmented(c, [b"\x05", b"\x00\x02", b"\x00", b"\x00", b"\x00"]),
                 "response")
expect("segmented_header_and_payload_response_zero", "status=0 valid=1" in out, out)

out = run_server(lambda c: segmented(c, [b"\x03\x00", b"\x02\x00", b"\x34", b"\x12"]),
                 "output")
expect("segmented_output_payload", "length=2 payload=3412" in out and
       "status=0 valid=1" in out, out)

out = run_server(lambda c: c.sendall(b"\x05\x00\x02\x00\x03\x00"),
                 "response_retry")
expect("response_error_preserves_code", "first_kind=9 first_dsp=3" in out and
       "first_error=instance=axis_alpha stage=wait_response category=dsp_response dsp_error=3" in out,
       out)
expect("fatal_error_invalid_and_no_reconnect", "valid=0" in out and
       "retry_status=-1" in out, out)

out = run_server(lambda c: c.sendall(b"\x05\x00\x04\x00ABCD"), "response")
expect("bad_response_length", "kind=7" in out and "valid=0" in out and
       "expected_length=2 actual_length=4" in out, out)

out = run_server(lambda c: c.sendall(b"\x04\x00\x00\x00"), "response")
expect("wrong_message_type_text", "kind=6" in out and "valid=0" in out and
       "expected_type=5 actual_type=4" in out, out)

out = run_server(lambda c: c.sendall(b"\x05\x00"), "response")
expect("header_truncated", "kind=5" in out and "valid=0" in out and
       "expected_length=4 actual_length=2" in out, out)

out = run_server(lambda c: c.sendall(b"\x05\x00\x02\x00\x00"), "response")
expect("payload_truncated", "kind=5" in out and "valid=0" in out and
       "expected_length=2 actual_length=1" in out, out)

out = run_server(lambda c: time.sleep(0.7), "response", timeout=3)
expect("receive_timeout", "kind=2" in out and "valid=0" in out, out)


def trickle(connection):
    for byte in b"\x05\x00\x02\x00\x00\x00":
        try:
            connection.sendall(bytes([byte]))
        except OSError:
            break
        time.sleep(0.09)


out = run_server(trickle, "response_short_timeout", timeout=3)
elapsed_text = out.split("client_elapsed_ms=")[1].split()[0]
expect("whole_operation_deadline", "kind=2" in out and int(elapsed_text) < 400,
       out)


received = 0


def receive_large(connection):
    global received
    while True:
        part = connection.recv(4096)
        if not part:
            break
        received += len(part)
        time.sleep(0.0005)


out = run_server(receive_large, "send_large", timeout=10)
expect("partial_send_eventually_complete", received == 8 * 1024 * 1024 and
       "status=0 valid=1" in out, f"received={received} {out}")

out = run_server(lambda c: None, "zero")
expect("zero_length_null_buffer", "status=0 valid=1" in out, out)

probe = socket.socket()
probe.bind(("127.0.0.1", 0))
closed_port = probe.getsockname()[1]
probe.close()
result = subprocess.run([CLIENT, "127.0.0.1", str(closed_port), "connect_fail"],
                        cwd=INSTANCE_DIR, text=True, capture_output=True, timeout=3)
expect("connect_failure_invalid", result.returncode == 0 and
       "status=-1 valid=0" in result.stdout and
       ("category=timeout" in result.stdout or "os_error=" in result.stdout),
       result.stdout + result.stderr)

print("SUMMARY passed=15 failed=0")
