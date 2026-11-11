import type { Comment } from "./api";
import { formatTime } from "./format";

// The text of a comment is shown as text: React escapes it, so markup in a comment (SV-03, fixed in
// WP4.5) or in an assistant's suggestion (SV-12) is displayed, never run. Never use
// dangerouslySetInnerHTML here: the ESLint rule react/no-danger and a Semgrep rule block it.
export function CommentList({ comments }: { comments: Comment[] }) {
  return (
    <ul className="comments" aria-label="Comments">
      {comments.map((comment) => (
        <li key={comment.id}>
          <time dateTime={comment.created_at}>{formatTime(comment.created_at)}</time>
          <p className="comment-body">{comment.body}</p>
        </li>
      ))}
    </ul>
  );
}
