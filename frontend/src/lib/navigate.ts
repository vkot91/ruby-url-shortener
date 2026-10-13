/**
 * The one place this application leaves React's router and uses the browser's.
 *
 * A session that has ended has to end everywhere at once — every mounted query,
 * every open form, every tab of the dashboard — and `router.push` cannot do
 * that: it re-renders the same tree with the same stale caches in it. A full
 * navigation throws the tree away, which is the correct response to "the
 * credentials this page was built on are gone".
 *
 * It is a module of its own so that `src/lib/api.ts` can be tested without a
 * real `location`: a test mocks this one function and asserts the redirect
 * without jsdom trying to perform it.
 */
export function hardRedirect(path: string) {
  if (typeof window === "undefined") return;

  window.location.replace(path);
}

/** Where to send somebody whose session ended, so signing in resumes it. */
export function signInPath() {
  if (typeof window === "undefined") return "/sign-in";

  const here = `${window.location.pathname}${window.location.search}`;

  return here === "/" ? "/sign-in" : `/sign-in?next=${encodeURIComponent(here)}`;
}
