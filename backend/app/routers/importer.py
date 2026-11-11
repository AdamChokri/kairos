"""POST /api/tasks/import: tasks from a YAML document.

The body is data, never code (SV-04, fixed in WP4.5): it is read with a size limit, parsed with
the safe loader (no Python object tags, no aliases) and checked against a schema before anything
is stored.
"""

import yaml
from fastapi import APIRouter, HTTPException, Request, status
from pydantic import ValidationError

from app.db import DbSession
from app.deps import CurrentUser
from app.models import Task
from app.schemas import ImportDocument

router = APIRouter(prefix="/api/tasks", tags=["import"])

MAX_BODY_BYTES = 100_000


async def read_body(request: Request) -> bytes:
    """The request body, refused with 413 as soon as it passes the limit."""
    too_large = HTTPException(status.HTTP_413_CONTENT_TOO_LARGE, "The document is too large")
    declared = request.headers.get("content-length", "")
    if declared.isdigit() and int(declared) > MAX_BODY_BYTES:
        raise too_large
    chunks: list[bytes] = []
    size = 0
    async for chunk in request.stream():
        size += len(chunk)
        if size > MAX_BODY_BYTES:
            raise too_large
        chunks.append(chunk)
    return b"".join(chunks)


def parse_document(body: bytes) -> ImportDocument:
    invalid = HTTPException(
        status.HTTP_422_UNPROCESSABLE_CONTENT, "The body is not a valid YAML document"
    )
    try:
        # Aliases can blow a few hundred bytes up to gigabytes ("billion laughs"): refuse them.
        if any(
            isinstance(event, yaml.AliasEvent) for event in yaml.parse(body, Loader=yaml.SafeLoader)
        ):
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_CONTENT, "YAML aliases are not accepted"
            )
        document = yaml.safe_load(body)
    except yaml.YAMLError as error:
        raise invalid from error
    try:
        return ImportDocument.model_validate(document)
    except ValidationError as error:
        detail = error.errors(include_url=False, include_context=False, include_input=False)
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, detail) from error


@router.post("/import", status_code=status.HTTP_201_CREATED)
async def import_tasks(request: Request, user: CurrentUser, db: DbSession) -> dict[str, int]:
    document = parse_document(await read_body(request))
    tasks = [
        Task(title=item.title, description=item.description, owner_id=user.id)
        for item in document.tasks
    ]
    db.add_all(tasks)
    db.commit()
    return {"imported": len(tasks)}
