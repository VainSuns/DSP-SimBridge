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


def exact(connection, size):
    data = bytearray()
    while len(data) < size:
        part = connection.recv(size - len(data))
        if not part:
            break
        data.extend(part)
    return bytes(data)


def run(mode, handler=None, defines=()):
    listener = None
    failures = []
    accepts = []
    if handler is not None:
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
                    handler(connection)
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
    else:
        thread = None
    executable = CLIENT + "_" + mode + (".exe" if sys.platform == "win32" else "")
    gcc = ["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-pedantic-errors",
           "-DMATLAB_MEX_FILE", *defines, "-I" + INSTANCE_DIR,
           "-I" + os.path.dirname(INSTANCE_DIR),
           INSTANCE_DIR + "/axis_alpha_pc_socket.c",
           INSTANCE_DIR + "/axis_alpha_protocol.c",
           INSTANCE_DIR + "/axis_alpha_sfun_io.c",
           __file__.replace("run_s4_03_lifecycle.py", "s4_03_lifecycle_client.c"),
           "-o", executable]
    if sys.platform == "win32":
        gcc.append("-lws2_32")
    compiled = subprocess.run(gcc, text=True, capture_output=True)
    if compiled.returncode:
        raise AssertionError(compiled.stdout + compiled.stderr)
    result = subprocess.run([executable, mode], cwd=INSTANCE_DIR,
                            text=True, capture_output=True, timeout=4)
    if thread is not None:
        thread.join(timeout=3)
        if thread.is_alive():
            raise AssertionError("server did not stop")
    if failures:
        raise failures[0]
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr + f" rc={result.returncode}")
    if len(accepts) > 1:
        raise AssertionError(f"{mode}: unexpected reconnect")
    print(result.stdout.strip())


def response(code, keep_after_stop=False):
    def handler(connection):
        assert exact(connection, len(START)) == START
        connection.sendall(struct.pack("<HHH", 5, 2, code))
        if code == 0:
            assert exact(connection, len(STOP)) == STOP
            if keep_after_stop:
                time.sleep(0.25)
            assert connection.recv(1) == b""
        else:
            assert connection.recv(1) == b""
    return handler


run("success", response(0, True))
run("version_error", response(6))
run("hash_error", response(3))

probe = socket.socket()
probe.bind(("127.0.0.1", 0))
closed_port = probe.getsockname()[1]
probe.close()
original_port = PORT
PORT = closed_port
run("connect_timeout", defines=("-DCONNECT_TIMEOUT_MS=0u",))
PORT = original_port


def fail_start_send(connection):
    assert connection.recv(1) == b""


run("start_send_failure", fail_start_send)


def no_response(connection):
    assert exact(connection, len(START)) == START
    time.sleep(0.25)
    assert connection.recv(1) == b""


run("response_timeout", no_response)


def close_after_start(connection):
    assert exact(connection, len(START)) == START
    connection.sendall(struct.pack("<HHH", 5, 2, 0))
    time.sleep(0.05)
    connection.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))


run("stop_failure", close_after_start)


def expect_no_stop(connection):
    assert exact(connection, len(START)) == START
    connection.sendall(struct.pack("<HHH", 5, 2, 0))
    assert connection.recv(1) == b""


run("invalid_terminate", expect_no_stop)
print("SUMMARY passed=8 failed=0")
