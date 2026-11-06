import type { Comment } from "./api";

// SV-03 (security/seeded-vulns.md): the text of a comment is inserted as HTML, so a comment
// that contains markup runs in the browser of everyone who opens the task (stored XSS).
export function CommentList({ comments }: { comments: Comment[] }) {
  return (
    <ul aria-label="Comments">
      {comments.map((comment) => (
        <li key={comment.id} dangerouslySetInnerHTML={{ __html: comment.body }} />
      ))}
    </ul>
  );
}
