// The time of a comment. The API sends the moment in UTC, and the database column has no time zone, so the text can
// arrive without a "Z": it is UTC all the same, and read as local time it would be an hour (or more) out.
const formatter = new Intl.DateTimeFormat("en-GB", {
  day: "numeric",
  month: "short",
  hour: "2-digit",
  minute: "2-digit",
});

export function formatTime(value: string): string {
  if (!value) return "";
  const hasZone = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(value);
  const date = new Date(hasZone ? value : `${value}Z`);
  return Number.isNaN(date.getTime()) ? "" : formatter.format(date);
}
