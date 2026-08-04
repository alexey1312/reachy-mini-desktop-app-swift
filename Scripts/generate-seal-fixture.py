#!/usr/bin/env python3
"""Generate the known-answer vector for `WiFiPasswordSeal`.

Run by hand, never in CI — it exists so the Swift test can assert a *reproducible*
ciphertext against an implementation of the scheme that is not our own. The daemon
side is `daemon/app/routers/wifi_config.py` (`get_provisioning_key`,
`_open_sealed_psk`) in pollen-robotics/reachy_mini.

    python3 -m venv /tmp/seal && /tmp/seal/bin/pip install -q -r Scripts/seal-fixture-requirements.txt
    /tmp/seal/bin/python Scripts/generate-seal-fixture.py > Tests/ReachyKitTests/Fixtures/wifi_seal_vector.json

Keys and nonce are fixed so the output is stable. The SSID carries a space and the
PIN mixes case: both are fed into the key derivation (as AAD and as HKDF salt), so a
client that normalises either would still pass a test using plain ASCII.
"""

import base64
import json
import sys

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

INFO = b"reachy-mini-wifi-psk-v1"

ROBOT_PRIVATE = bytes(range(32))
CLIENT_PRIVATE = bytes(range(32, 64))
NONCE = bytes(range(0x10, 0x1C))  # 12 bytes

SSID = "Reachy Test Net"
PASSWORD = "correct horse battery staple"
PIN = "4A7f9"
KID = "0a1b2c3d"


def derive(shared: bytes) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=PIN.encode(), info=INFO).derive(shared)


def main() -> None:
    robot_private = X25519PrivateKey.from_private_bytes(ROBOT_PRIVATE)
    robot_public = robot_private.public_key()
    client_private = X25519PrivateKey.from_private_bytes(CLIENT_PRIVATE)

    key = derive(client_private.exchange(robot_public))
    ciphertext = AESGCM(key).encrypt(NONCE, PASSWORD.encode(), SSID.encode())

    # Reproduce what the daemon does on receipt. A vector that cannot be opened by
    # the other side is worse than no vector at all, so never emit one.
    reopened = AESGCM(derive(robot_private.exchange(client_private.public_key()))).decrypt(
        NONCE, ciphertext, SSID.encode()
    )
    if reopened.decode() != PASSWORD:
        sys.exit("round trip failed: the daemon side would not open this ciphertext")

    def b64(raw: bytes) -> str:
        return base64.b64encode(raw).decode()

    json.dump(
        {
            "ssid": SSID,
            "password": PASSWORD,
            "pin": PIN,
            "kid": KID,
            "robotPublicKey": b64(robot_public.public_bytes_raw()),
            "clientPrivateKey": b64(CLIENT_PRIVATE),
            "nonce": b64(NONCE),
            "expectedClientPublicKey": b64(client_private.public_key().public_bytes_raw()),
            "expectedCiphertext": b64(ciphertext),
        },
        sys.stdout,
        indent=2,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
