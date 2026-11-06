"""Comments on a task: GET and POST /api/tasks/{id}/comments.

The SPA shows the text as HTML (SV-03). The comment routes check the task id like the task
routes do (SV-06): nothing here looks at who owns the task.
"""

from fastapi import APIRouter, status
from sqlalchemy import select

from app.db import DbSession
from app.deps import CurrentUser
from app.models import Comment
from app.routers.tasks import get_task
from app.schemas import CommentIn, CommentOut

router = APIRouter(prefix="/api/tasks/{task_id}/comments", tags=["comments"])


@router.get("", response_model=list[CommentOut])
def list_comments(task_id: int, user: CurrentUser, db: DbSession) -> list[Comment]:
    task = get_task(task_id, db)
    return list(db.scalars(select(Comment).where(Comment.task_id == task.id).order_by(Comment.id)))


@router.post("", response_model=CommentOut, status_code=status.HTTP_201_CREATED)
def add_comment(task_id: int, body: CommentIn, user: CurrentUser, db: DbSession) -> Comment:
    task = get_task(task_id, db)
    comment = Comment(task_id=task.id, author_id=user.id, body=body.body)
    db.add(comment)
    db.commit()
    return comment
