/**
 * Sanitize an ID used in file paths to prevent path traversal attacks.
 * Strips everything except alphanumeric chars, hyphens, underscores, and dots (no leading dot).
 */
export function sanitizeId(id: string): string {
  // Remove any path separators and null bytes
  const cleaned = id.replace(/[/\\:\0]/g, '').replace(/\.\./g, '');
  // Only allow safe characters
  const safe = cleaned.replace(/[^a-zA-Z0-9_\-\.]/g, '');
  // Prevent hidden files (leading dot)
  return safe.replace(/^\.+/, '');
}
