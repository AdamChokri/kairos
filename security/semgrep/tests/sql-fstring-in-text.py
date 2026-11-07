"""Fixture for kairos.sql-fstring-in-text."""

from sqlalchemy import select, text


def search(db, user, search_text, table):
    # ruleid: kairos.sql-fstring-in-text
    q1 = text(f"SELECT * FROM tasks WHERE title LIKE '%{search_text}%'")

    # ruleid: kairos.sql-fstring-in-text
    q2 = text(
        "SELECT id, title FROM tasks "
        f"WHERE owner_id = {user.id} AND lower(title) LIKE lower('%{search_text}%') ORDER BY id"
    )

    # ruleid: kairos.sql-fstring-in-text
    q3 = text("SELECT * FROM tasks WHERE title = '" + search_text + "'")

    # ruleid: kairos.sql-fstring-in-text
    q4 = text("SELECT * FROM tasks WHERE title = '%s'" % search_text)

    # ruleid: kairos.sql-fstring-in-text
    q5 = text("SELECT * FROM {}".format(table))

    # ruleid: kairos.sql-fstring-in-text
    db.execute(f"DELETE FROM tasks WHERE id = {search_text}")

    # ruleid: kairos.sql-fstring-in-text
    db.execute("DELETE FROM tasks WHERE title = '" + search_text + "'")

    # ok: kairos.sql-fstring-in-text
    ok1 = text("SELECT * FROM tasks WHERE owner_id = :owner AND lower(title) LIKE lower(:pattern)")
    db.execute(ok1, {"owner": user.id, "pattern": f"%{search_text}%"})

    # ok: kairos.sql-fstring-in-text
    ok2 = select(table).where(table.c.title.ilike(f"%{search_text}%"))

    # ok: kairos.sql-fstring-in-text
    ok3 = text("SELECT count(*) FROM tasks")

    # ok: kairos.sql-fstring-in-text
    db.execute("DELETE FROM tasks WHERE id = :id", {"id": search_text})

    return q1, q2, q3, q4, q5, ok2, ok3
