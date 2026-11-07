"""Fixture for kairos.unsafe-yaml-load."""

import yaml


def parse(body, other):
    # ruleid: kairos.unsafe-yaml-load
    a = yaml.load(body, Loader=yaml.Loader)

    # ruleid: kairos.unsafe-yaml-load
    b = yaml.load(body, Loader=yaml.UnsafeLoader)

    # ruleid: kairos.unsafe-yaml-load
    c = yaml.load(body, Loader=yaml.FullLoader)

    # ruleid: kairos.unsafe-yaml-load
    d = yaml.load(body, Loader=yaml.CLoader)

    # ok: kairos.unsafe-yaml-load
    e = yaml.safe_load(body)

    # ok: kairos.unsafe-yaml-load
    f = yaml.load(body, Loader=yaml.SafeLoader)

    # ok: kairos.unsafe-yaml-load
    g = yaml.load(body, Loader=yaml.CSafeLoader)

    # ok: kairos.unsafe-yaml-load
    h = other.load(body, Loader=yaml.Loader)

    return a, b, c, d, e, f, g, h
