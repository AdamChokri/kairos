"""POST /api/tasks/import: tasks from a YAML document.

Seeded weakness SV-04 (security/seeded-vulns.md): the request body is parsed with the unsafe
loader, which builds any Python object the document names. WP4.5 uses safe_load plus a schema.
"""

import yaml
from fastapi import APIRouter, Request, status

from app.db import DbSession
from app.deps import CurrentUser
from app.models import Task

router = APIRouter(prefix="/api/tasks", tags=["import"])


@router.post("/import", status_code=status.HTTP_201_CREATED)
async def import_tasks(request: Request, user: CurrentUser, db: DbSession) -> dict[str, int]:
    document = yaml.load(await request.body(), Loader=yaml.Loader)  # SV-04
    tasks = [
        Task(title=item["title"], description=item.get("description", ""), owner_id=user.id)
        for item in document["tasks"]
    ]
    db.add_all(tasks)
    db.commit()
    return {"imported": len(tasks)}
