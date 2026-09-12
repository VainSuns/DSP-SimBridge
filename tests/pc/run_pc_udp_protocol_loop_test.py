"""Render the production UDP binding and run the S4-04 localhost loop."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
TEMPLATE_ROOT = ROOT / "app" / "templates"
ERROR_HEADER = ROOT / "simulink" / "c2837x_block_pc_error.h"
FIXTURE = ROOT / "tests" / "pc" / "pc_udp_protocol_loop_test.c"


def render(template):
    return (TEMPLATE_ROOT / template).read_text(encoding="utf-8").replace(
        "@NAME@", "axis_alpha").replace("@MACRO@", "AXIS_ALPHA").replace(
        "@TYPED@", "AxisAlpha")


def bind_udp_protocol(source, header):
    """Apply the renderer's bind_udp_protocol substitutions to one V1 source."""
    header = header.replace(
        '#include "axis_alpha_pc_socket.h"',
        '#include "axis_alpha_pc_udp.h"')
    header = header.replace("AxisAlphaPcSocket", "AxisAlphaPcUdpSocket")
    header = header.replace("AxisAlphaPcDeadline", "AxisAlphaPcUdpDeadline")

    source = source.replace("AxisAlphaPcSocket", "AxisAlphaPcUdpSocket")
    source = source.replace("AxisAlphaPcDeadline", "AxisAlphaPcUdpDeadline")
    source = source.replace("axis_alpha_pc_socket_close",
                            "axis_alpha_pc_udp_close")
    source = source.replace("axis_alpha_pc_socket_send_all_until",
                            "axis_alpha_pc_udp_send_all_until")
    source = source.replace("axis_alpha_pc_socket_recv_exact_until",
                            "axis_alpha_pc_udp_recv_exact_until")
    source = source.replace("axis_alpha_pc_deadline_start",
                            "axis_alpha_pc_udp_deadline_start")
    return source, header


def static_contract_checks(udp_source, udp_header, protocol_source,
                           protocol_header):
    assert "SOCK_DGRAM" in udp_source
    assert "IPPROTO_UDP" in udp_source
    assert "SOCK_STREAM" not in udp_source
    assert "IPPROTO_TCP" not in udp_source
    assert "datagram_staging" in udp_source
    assert "AxisAlphaPcUdpSocket *socket" in protocol_header
    assert "AxisAlphaPcUdpSocket *socket" in protocol_source
    assert "AxisAlphaPcUdpDeadline deadline" in protocol_source
    assert "axis_alpha_pc_udp_send_all_until" in protocol_source
    assert "axis_alpha_pc_udp_recv_exact_until" in protocol_source
    assert "axis_alpha_pc_udp_close" in protocol_source
    assert "AxisAlphaPcSocket" not in protocol_source
    assert "AxisAlphaPcDeadline" not in protocol_source
    assert "pc_socket_" not in protocol_source
    assert "#include \"axis_alpha_pc_udp.h\"" in protocol_header
    print("PRODUCTION_DERIVED_UDP_BINDING=PASS")


def run():
    udp_source = render("pc_udp.c.in")
    udp_header = render("pc_udp.h.in")
    protocol_source, protocol_header = bind_udp_protocol(
        render("protocol.c.in"), render("protocol.h.in"))
    static_contract_checks(udp_source, udp_header, protocol_source,
                           protocol_header)

    compiler = shutil.which("gcc")
    if compiler is None:
        print("COMPILE=NOT_EXECUTED / CAPABILITY (gcc unavailable)")
        return 0

    with tempfile.TemporaryDirectory(prefix="udp_s4_04_") as folder_name:
        folder = Path(folder_name)
        (folder / "axis_alpha_pc_udp.c").write_text(
            udp_source, encoding="utf-8", newline="\n")
        (folder / "axis_alpha_pc_udp.h").write_text(
            udp_header, encoding="utf-8", newline="\n")
        (folder / "axis_alpha_protocol.c").write_text(
            protocol_source, encoding="utf-8", newline="\n")
        (folder / "axis_alpha_protocol.h").write_text(
            protocol_header, encoding="utf-8", newline="\n")
        shutil.copyfile(ERROR_HEADER, folder / "axis_alpha_pc_error.h")
        executable = folder / ("pc_udp_protocol_loop_test.exe"
                                if os.name == "nt"
                                else "pc_udp_protocol_loop_test")
        command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror",
                   "-pedantic-errors", f"-I{folder}",
                   str(folder / "axis_alpha_pc_udp.c"),
                   str(folder / "axis_alpha_protocol.c"), str(FIXTURE),
                   "-o", str(executable)]
        if os.name == "nt":
            command.append("-lws2_32")
        compiled = subprocess.run(command, capture_output=True, text=True)
        if compiled.returncode != 0:
            print(compiled.stdout, end="")
            print(compiled.stderr, end="")
            return compiled.returncode
        print("COMPILE=PASS generated_pc_udp_and_bound_protocol")

        executed = subprocess.run([str(executable)], capture_output=True,
                                  text=True, timeout=10)
        print(executed.stdout, end="")
        print(executed.stderr, end="")
        return executed.returncode


if __name__ == "__main__":
    raise SystemExit(run())
