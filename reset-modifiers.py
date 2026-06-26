#!/usr/bin/env python3
"""Release all X11 modifier keys via XTest to fix stuck modifier state."""

from __future__ import annotations

import ctypes
import ctypes.util
import os
import sys

_MODIFIER_KEYCODES: list[int] = [
    50,   # Shift_L
    62,   # Shift_R
    37,   # Control_L
    105,  # Control_R
    64,   # Alt_L
    108,  # Alt_R
    133,  # Super_L
    66,   # Caps_Lock
]


def release_modifiers(display_name: bytes) -> None:
    """Send key-release events for all modifier keycodes and close the display."""
    libx11_name = ctypes.util.find_library("X11")
    libxtst_name = ctypes.util.find_library("Xtst")

    if not libx11_name:
        print("error: libX11 not found", file=sys.stderr)
        sys.exit(1)
    if not libxtst_name:
        print("error: libXtst not found", file=sys.stderr)
        sys.exit(1)

    libx11 = ctypes.cdll.LoadLibrary(libx11_name)
    libxtst = ctypes.cdll.LoadLibrary(libxtst_name)

    # ctypes cdll attributes are assigned dynamically at runtime; mypy cannot resolve them
    libx11.XOpenDisplay.restype = ctypes.c_void_p  # type: ignore[attr-defined]
    libx11.XOpenDisplay.argtypes = [ctypes.c_char_p]  # type: ignore[attr-defined]

    display = libx11.XOpenDisplay(display_name)  # type: ignore[attr-defined]
    if not display:
        print(f"error: cannot open display {display_name.decode()}", file=sys.stderr)
        sys.exit(1)

    for keycode in _MODIFIER_KEYCODES:
        libxtst.XTestFakeKeyEvent(display, keycode, False, 0)  # type: ignore[attr-defined]

    libx11.XFlush(display)  # type: ignore[attr-defined]
    libx11.XCloseDisplay(display)  # type: ignore[attr-defined]


def main() -> None:
    """Read DISPLAY from environment and release all modifier keys."""
    display = os.environb.get(b"DISPLAY", b":0")
    release_modifiers(display)


if __name__ == "__main__":
    main()
