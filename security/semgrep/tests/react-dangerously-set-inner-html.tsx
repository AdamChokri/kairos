// Fixture for kairos.react-dangerously-set-inner-html.
type Comment = { id: number; body: string };

export function Bad({ comment }: { comment: Comment }) {
  // ruleid: kairos.react-dangerously-set-inner-html
  const a = <li dangerouslySetInnerHTML={{ __html: comment.body }} />;
  // ruleid: kairos.react-dangerously-set-inner-html
  const b = <li key={comment.id} dangerouslySetInnerHTML={{ __html: comment.body }} />;
  // ruleid: kairos.react-dangerously-set-inner-html
  const c = <li dangerouslySetInnerHTML={{ __html: `<b>${comment.body}</b>` }}></li>;
  return (
    <ul>
      {a}
      {b}
      {c}
    </ul>
  );
}

export function Good({ comment }: { comment: Comment }) {
  // ok: kairos.react-dangerously-set-inner-html
  const a = <li>{comment.body}</li>;
  // ok: kairos.react-dangerously-set-inner-html
  const b = <li dangerouslySetInnerHTML={{ __html: "<b>fixed text</b>" }} />;
  // ok: kairos.react-dangerously-set-inner-html
  const c = <li title="dangerouslySetInnerHTML is only a word here">{comment.body}</li>;
  return (
    <ul>
      {a}
      {b}
      {c}
    </ul>
  );
}
