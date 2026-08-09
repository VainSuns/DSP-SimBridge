import os
import socket
import struct
import subprocess
import sys
import threading
import time


CLIENT, INSTANCE_DIR, PORT = sys.argv[1], sys.argv[2], int(sys.argv[3])
START = struct.pack("<HHHI", 1, 6, 1, 0x12345678)
STOP = struct.pack("<HH", 4, 0)
INPUT_DATA = bytes.fromhex(
    "fe ff 34 12 dc fe eb 32 a4 f8 ef cd ab 89"
)
INPUT_DATA += b"".join(struct.pack("<I", bits) for bits in (
    0x00000000, 0x80000000, 0x7f800000, 0xff800000,
    0x7fc000a5, 0x00000001, 0x3f800000
))
INPUT_DATA += b"".join(struct.pack("<Q", bits) for bits in (
    0x0000000000000000, 0x8000000000000000,
    0x7ff0000000000000, 0xfff0000000000000,
    0x7ff80000000000a5, 0x0000000000000001,
    0x3ff0000000000000
))
OUTPUT_DATA = bytes.fromhex(
    "01 80 cd ab fe ff ff ff 98 ba dc fe"
)
OUTPUT_DATA += b"".join(struct.pack("<I", bits) for bits in (
    0x00000000, 0x80000000, 0x7f800000, 0xff800000,
    0x7fc000a5, 0x00000001, 0x3f800000
))
OUTPUT_DATA += b"".join(struct.pack("<Q", bits) for bits in (
    0x0000000000000000, 0x8000000000000000,
    0x7ff0000000000000, 0xfff0000000000000,
    0x7ff80000000000a5, 0x0000000000000001,
    0x3ff0000000000000
))


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


def input_frame(step):
    return frame(2, struct.pack("<I", step) + INPUT_DATA)


def output_frame(step):
    return frame(3, struct.pack("<I", step) + OUTPUT_DATA)


def compile_client(path, injected=False):
    gcc = [
        "gcc", "-std=c11", "-Wall", "-Wextra", "-Werror",
        "-Wno-unused-function", "-pedantic-errors", "-DMATLAB_MEX_FILE",
    ]
    if injected:
        gcc.append("-DINJECT_DECODE_FAILURE")
    gcc += [
        "-I" + INSTANCE_DIR,
        "-I" + os.path.dirname(INSTANCE_DIR),
        "-I" + os.path.dirname(INSTANCE_DIR) + "/axis_beta",
        INSTANCE_DIR + "/axis_alpha_pc_socket.c",
        INSTANCE_DIR + "/axis_alpha_protocol.c",
        INSTANCE_DIR + "/axis_alpha_sfun_io.c",
        os.path.dirname(INSTANCE_DIR) + "/axis_beta/axis_beta_pc_socket.c",
        os.path.dirname(INSTANCE_DIR) + "/axis_beta/axis_beta_sfun_io.c",
        __file__.replace("run_s4_04_step.py", "s4_04_step_client.c"),
        "-o", path,
    ]
    if sys.platform == "win32":
        gcc.append("-lws2_32")
    result = subprocess.run(gcc, text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)


NORMAL = CLIENT + (".exe" if sys.platform == "win32" else "")
INJECTED = CLIENT + "_injected" + (".exe" if sys.platform == "win32" else "")
compile_client(NORMAL)
compile_client(INJECTED, True)


def run(mode, reply, expected_steps=(0,), injected=False):
    failures = []
    accepts = []
    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", PORT))
    listener.listen(2)
    listener.settimeout(2)

    def serve():
        try:
            connection, _ = listener.accept()
            accepts.append(1)
            with connection:
                assert exact(connection, len(START)) == START
                connection.sendall(frame(5, struct.pack("<H", 0)))
                for index, step in enumerate(expected_steps):
                    expected = input_frame(step)
                    assert exact(connection, len(expected)) == expected
                    reply(connection, step, index)
                if mode in ("success", "wrap"):
                    assert exact(connection, len(STOP)) == STOP
                connection.settimeout(0.5)
                try:
                    assert connection.recv(1) == b""
                except OSError:
                    if mode != "disconnect":
                        raise
            listener.settimeout(0.2)
            try:
                extra, _ = listener.accept()
                accepts.append(1)
                extra.close()
            except TimeoutError:
                pass
        except Exception as exc:
            failures.append(exc)
        finally:
            listener.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    executable = INJECTED if injected else NORMAL
    result = subprocess.run([executable, mode], cwd=INSTANCE_DIR,
                            text=True, capture_output=True, timeout=5)
    thread.join(timeout=3)
    if thread.is_alive():
        raise AssertionError(f"{mode}: server did not stop")
    if failures:
        raise failures[0]
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr + f" rc={result.returncode}")
    if len(accepts) != 1:
        raise AssertionError(f"{mode}: unexpected connection count {len(accepts)}")
    print(result.stdout.strip())


def valid(connection, step, _):
    connection.sendall(output_frame(step))


run("success", valid, (0, 1))
run("wrap", valid, (0xFFFFFFFF,))
run("response_error", lambda c, _s, _i: c.sendall(frame(5, struct.pack("<H", 7))))
run("response_zero", lambda c, _s, _i: c.sendall(frame(5, struct.pack("<H", 0))))
run("wrong_type", lambda c, _s, _i: c.sendall(frame(4)))
run("short", lambda c, _s, _i: c.sendall(frame(3, struct.pack("<I", 0) + OUTPUT_DATA[:-2])))
run("long", lambda c, _s, _i: c.sendall(struct.pack("<HH", 3, 102)))
run("odd", lambda c, _s, _i: c.sendall(struct.pack("<HH", 3, 99)))
run("wrong_step", lambda c, _s, _i: c.sendall(output_frame(1)))


def header_truncated(connection, _step, _index):
    connection.sendall(b"\x03\x00")
    connection.shutdown(socket.SHUT_WR)


run("header_truncated", header_truncated)


def payload_truncated(connection, _step, _index):
    connection.sendall(struct.pack("<HH", 3, 100) + output_frame(0)[4:12])
    connection.shutdown(socket.SHUT_WR)


run("payload_truncated", payload_truncated)


def timeout(connection, _step, _index):
    time.sleep(0.25)


run("timeout", timeout)


def disconnect(connection, _step, _index):
    connection.shutdown(socket.SHUT_RDWR)


run("disconnect", disconnect)
run("decode_failure", valid, injected=True)
run("port_failure", valid)
print("SUMMARY passed=15 failed=0")
