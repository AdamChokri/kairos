import type { Comment } from "./api";

// The text of a comment is shown as text: React escapes it, so markup in a comment (SV-03, fixed in
// WP4.5) or in an assistant's suggestion (SV-12) is displayed, never run. Never use
// dangerouslySetInnerHTML here: the ESLint rule react/no-danger and a Semgrep rule block it.
export function CommentList({ comments }: { comments: Comment[] }) {
  return (
    <ul aria-label="Comments">
      {comments.map((comment) => (
        <li key={comment.id}>{comment.body}</li>
      ))}
    </ul>
  );
}
