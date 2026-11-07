"""Fixture for kairos.nosql-operator-injection (Kairos has no MongoDB: this proves the rule only)."""

from flask import request


def login(users):
    # ruleid: kairos.nosql-operator-injection
    return users.find_one(request.json)


def login_fields(users):
    body = request.get_json()
    # ruleid: kairos.nosql-operator-injection
    return users.find_one({"name": body["name"], "password": body["password"]})


def search(items):
    # ruleid: kairos.nosql-operator-injection
    return items.find({"owner": request.args["owner"]})


def where_clause(items):
    # ruleid: kairos.nosql-operator-injection
    return items.find({"$where": "this.owner == '" + request.args["owner"] + "'"})


async def delete_all(items, request):
    query = await request.json()
    # ruleid: kairos.nosql-operator-injection
    items.delete_many(query)


def login_safe(users):
    body = request.get_json()
    # ok: kairos.nosql-operator-injection
    return users.find_one({"name": str(body["name"]), "password": str(body["password"])})


def search_safe(items):
    # ok: kairos.nosql-operator-injection
    return items.find({"owner": str(request.args["owner"])})


def constant_filter(items):
    # ok: kairos.nosql-operator-injection
    return items.find({"done": False})
