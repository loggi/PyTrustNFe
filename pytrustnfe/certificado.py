# -*- coding: utf-8 -*-
# © 2016 Danimar Ribeiro, Trustcode
# License AGPL-3.0 or later (http://www.gnu.org/licenses/agpl.html).

import os
import tempfile

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa
from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, NoEncryption
from cryptography.hazmat.primitives.serialization.pkcs12 import load_key_and_certificates


def _pfx_password_bytes(password):
    if isinstance(password, str):
        return password.encode()
    return password


def load_privatekey_from_pfx(pfx: bytes, password):
    """RSA/EC private key from PKCS#12 (replacement for removed OpenSSL.crypto.load_pkcs12)."""
    pk, _cert, _rest = load_key_and_certificates(pfx, _pfx_password_bytes(password))
    return pk


def rsa_or_ec_sha1_sign(private_key, message) -> bytes:
    """Match legacy ``OpenSSL.crypto.sign(..., \"SHA1\")`` for RSA (PKCS1v15) or EC (ECDSA)."""
    data = message.encode("utf-8") if isinstance(message, str) else message
    if isinstance(private_key, rsa.RSAPrivateKey):
        return private_key.sign(data, padding.PKCS1v15(), hashes.SHA1())
    if isinstance(private_key, ec.EllipticCurvePrivateKey):
        return private_key.sign(data, ec.ECDSA(hashes.SHA1()))
    raise TypeError("Unsupported private key type for SHA1 signing")


class Certificado(object):
    def __init__(self, pfx, password):
        self.pfx = pfx
        self.password = password

    def save_pfx(self):
        pfx_temp = tempfile.mkstemp()[1]
        arq_temp = open(pfx_temp, "wb")
        arq_temp.write(self.pfx)
        arq_temp.close()
        return pfx_temp


def extract_cert_and_key_from_pfx(pfx, password):
    pk, cert, _extra = load_key_and_certificates(pfx, _pfx_password_bytes(password))
    if cert is None:
        raise ValueError("PKCS#12 bundle has no certificate")
    key_pem = pk.private_bytes(
        Encoding.PEM,
        PrivateFormat.PKCS8,
        NoEncryption(),
    ).decode()
    cert_pem = cert.public_bytes(Encoding.PEM).decode()
    return cert_pem, key_pem


def save_cert_key(cert, key):
    fd_cert, cert_temp = tempfile.mkstemp()
    fd_key, key_temp = tempfile.mkstemp()

    os.write(fd_cert, cert.encode())
    os.close(fd_cert)

    os.write(fd_key, key.encode())
    os.close(fd_key)

    return cert_temp, key_temp
