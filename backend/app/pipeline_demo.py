"""Scratch module for the pipeline test run. Never merged."""

import hashlib


def fingerprint(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()
