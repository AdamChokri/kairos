"""Tasks: list and search, create, read, update, delete (plan section 3.2).

Seeded weaknesses (security/seeded-vulns.md):
  SV-02  the search text is pasted into the SQL string (injection).
  SV-06  a task is fetched by its id alone: any logged-in user can read, change or delete
         anyone's task (insecure direct object reference). Comments share the same flaw.
"""

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import delete, select, text

from app.db import DbSession
from app.deps import CurrentUser
from app.models import Comment, Task
from app.schemas import TaskIn, TaskOut

router = APIRouter(prefix="/api/tasks", tags=["tasks"])


def get_task(task_id: int, db: DbSession) -> Task:
    task = db.get(Task, task_id)  # SV-06: no check that the task belongs to the caller
    if task is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Task not found")
    return task


@router.get("", response_model=list[TaskOut])
def list_tasks(user: CurrentUser, db: DbSession, search: str | None = None) -> list[TaskOut]:
    if search:
        # SV-02: the search text is part of the SQL string.
        query = text(
            "SELECT id, title, description, done, owner_id FROM tasks "
            f"WHERE owner_id = {user.id} AND lower(title) LIKE lower('%{search}%') ORDER BY id"
        )
        return [TaskOut(**row._mapping) for row in db.execute(query)]
    tasks = db.scalars(select(Task).where(Task.owner_id == user.id).order_by(Task.id))
    return [TaskOut.model_validate(task) for task in tasks]


@router.post("", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
def create_task(body: TaskIn, user: CurrentUser, db: DbSession) -> Task:
    task = Task(**body.model_dump(), owner_id=user.id)
    db.add(task)
    db.commit()
    return task


@router.get("/{task_id}", response_model=TaskOut)
def read_task(task_id: int, user: CurrentUser, db: DbSession) -> Task:
    return get_task(task_id, db)


@router.put("/{task_id}", response_model=TaskOut)
def update_task(task_id: int, body: TaskIn, user: CurrentUser, db: DbSession) -> Task:
    task = get_task(task_id, db)
    task.title = body.title
    task.description = body.description
    task.done = body.done
    db.commit()
    return task


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: int, user: CurrentUser, db: DbSession) -> None:
    task = get_task(task_id, db)
    db.execute(delete(Comment).where(Comment.task_id == task.id))
    db.delete(task)
    db.commit()
