"""A PTY line editor that discards input before its composer is available."""
import os
import sys
import termios
import time
import tty

tty.setraw(sys.stdin.fileno())
time.sleep(0.5)
termios.tcflush(sys.stdin.fileno(), termios.TCIFLUSH)
os.write(1, b'\x1b[?2004h\x1b[?25l\x1b[2J\x1b[H' + '› 1. Trust and continue'.encode())
time.sleep(0.4)
termios.tcflush(sys.stdin.fileno(), termios.TCIFLUSH)
os.write(1, b'\x1b[2J\x1b[H' + '› '.encode() + b'\x1b[?25h')
while True:
    data = os.read(0, 65536)
    if not data:
        break
    if b'\r' in data:
        os.write(1, b'UNEXPECTED_SUBMIT')
    data = data.replace(b'\x1b[200~', b'').replace(b'\x1b[201~', b'')
    os.write(1, data.replace(b'\n', b'\r\n'))
