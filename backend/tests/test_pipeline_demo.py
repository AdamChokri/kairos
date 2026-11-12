"""Scratch test for the pipeline test run. Never merged."""

from app.pipeline_demo import fingerprint


def test_fingerprint_is_a_sha256_hexdigest():
    assert len(fingerprint("kairos")) == 64
