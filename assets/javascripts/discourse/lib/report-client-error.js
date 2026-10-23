/**
 * Report an error that the plugin handles itself so it stays visible.
 * Logs to the browser console and forwards to window.onerror, which hands it
 * to Logster's JS error reporter (shown under /logs when the site has
 * enable_js_error_reporting turned on).
 *
 * @param {string} context - short description of what failed
 * @param {Error} error - the caught error
 */
export default function reportClientError(context, error) {
  const message = `[vzekc-verlosung] ${context}: ${error?.message || error}`;

  // eslint-disable-next-line no-console
  console.error(message, error);

  window.onerror?.(message, null, null, null, error);
}
