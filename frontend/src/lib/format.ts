/**
 * The three presentation decisions design.md §6.3 makes about a table row, kept
 * out of the row component so they can be tested without rendering one.
 */

/**
 * Splits an API-issued `short_url` into the two halves `<ShortLink>` renders
 * differently: the domain in muted, the code in foreground (design.md P1).
 *
 * Derived from the URL rather than configured on the client. The short domain
 * is deployment configuration the server already applied, and a second copy in
 * a `NEXT_PUBLIC_` variable would be one more thing that can disagree with it —
 * silently, and only in the one string every visitor is asked to type.
 */
export function splitShortUrl(shortUrl: string): { domain: string; code: string } {
  try {
    const url = new URL(shortUrl);

    return { domain: url.host, code: url.pathname.replace(/^\//, "") };
  } catch {
    return { domain: "", code: shortUrl };
  }
}

/**
 * Middle truncation, because the ends of a destination URL are the informative
 * parts: the host says where it goes and the last path segment says what it is,
 * while the middle is usually a category tree nobody reads. Tail truncation
 * would keep the half that identifies nothing.
 *
 * The full URL still travels as the `title` attribute, so nothing is lost.
 */
export function middleTruncate(value: string, maxLength = 64): string {
  if (value.length <= maxLength) return value;

  const half = Math.floor((maxLength - 1) / 2);

  return `${value.slice(0, half)}…${value.slice(value.length - half)}`;
}

const RELATIVE_LIMIT_DAYS = 7;

const RELATIVE = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
const ABSOLUTE = new Intl.DateTimeFormat("en", { day: "numeric", month: "short", year: "numeric" });

/**
 * Relative under a week, absolute after (design.md §6.3).
 *
 * The switch is the point: "3 days ago" is how somebody thinks about a link
 * they made this week, and "412 days ago" is how nobody thinks about anything.
 */
export function formatCreatedAt(iso: string, now = new Date()): string {
  const created = new Date(iso);
  const elapsedMs = now.getTime() - created.getTime();
  const days = Math.floor(elapsedMs / 86_400_000);

  if (days >= RELATIVE_LIMIT_DAYS) return ABSOLUTE.format(created);

  if (days >= 1) return RELATIVE.format(-days, "day");

  const hours = Math.floor(elapsedMs / 3_600_000);

  if (hours >= 1) return RELATIVE.format(-hours, "hour");

  const minutes = Math.floor(elapsedMs / 60_000);

  return minutes >= 1 ? RELATIVE.format(-minutes, "minute") : "just now";
}
