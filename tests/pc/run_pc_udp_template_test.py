"""Render and run the focused UDP-S4-02 host transport test."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
TEMPLATE_ROOT = ROOT / "app" / "templates"
ERROR_HEADER = ROOT / "simulink" / "c2837x_block_pc_error.h"
FIXTURE = ROOT / "tests" / "pc" / "pc_udp_host_test.c"


def render(template):
    return (TEMPLATE_ROOT / template).read_text(encoding="utf-8").replace(
        "@NAME@", "axis_alpha").replace("@MACRO@", "AXIS_ALPHA").replace(
        "@TYPED@", "AxisAlpha")


def static_contract_checks(source, header):
    assert "SOCK_DGRAM" in source
    assert "IPPROTO_UDP" in source
    assert "SOCK_STREAM" not in source
    assert "IPPROTO_TCP" not in source
    assert not re.search(r"\bbind\s*\(", source)
    assert "datagram_staging" in source
    assert "PC_UDP_MAX_DATAGRAM_SIZE 1472u" in header
    assert "recv_exact_until" in source
    assert source.count("recv(") == 1
    assert "retry" not in source.lower()
    assert "retrans" not in source.lower()
    assert source.count("send(") == 1
    start = source.index("int axis_alpha_pc_udp_send_datagram_until(")
    end = source.index("int axis_alpha_pc_udp_send_datagram(", start)
    send_body = source[start:end]
    assert "while" not in send_body
    assert "for (" not in send_body
    assert "done" not in send_body
    assert "offset" not in send_body
    assert "deadline_remaining" in source
    assert "CLOCK_MONOTONIC" in source
    assert "poll(" in source
    assert "select(" in source


def run():
    source = render("pc_udp.c.in")
    header = render("pc_udp.h.in")
    static_contract_checks(source, header)
    print("STATIC_CONTRACT=PASS")

    compiler = shutil.which("gcc")
    if compiler is None:
        print("COMPILE=NOT_EXECUTED / CAPABILITY (gcc unavailable)")
        return 0

    with tempfile.TemporaryDirectory(prefix="udp_s4_01_") as folder_name:
        folder = Path(folder_name)
        (folder / "axis_alpha_pc_udp.c").write_text(source, encoding="utf-8",
                                                     newline="\n")
        (folder / "axis_alpha_pc_udp.h").write_text(header, encoding="utf-8",
                                                     newline="\n")
        shutil.copyfile(ERROR_HEADER, folder / "axis_alpha_pc_error.h")
        executable = folder / ("pc_udp_host_test.exe" if os.name == "nt"
                                else "pc_udp_host_test")
        command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror",
                   "-pedantic-errors", f"-I{folder}",
                   str(folder / "axis_alpha_pc_udp.c"), str(FIXTURE),
                   "-o", str(executable)]
        if os.name == "nt":
            command.append("-lws2_32")
        compiled = subprocess.run(command, capture_output=True, text=True)
        if compiled.returncode != 0:
            print(compiled.stdout, end="")
            print(compiled.stderr, end="")
            return compiled.returncode
        print("COMPILE=PASS")

        executed = subprocess.run([str(executable)], capture_output=True,
                                   text=True)
        print(executed.stdout, end="")
        print(executed.stderr, end="")
        return executed.returncode


if __name__ == "__main__":
    raise SystemExit(run())
