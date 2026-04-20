const commonDirectives = [
  "default-src 'self'",
  "base-uri 'self'",
  "frame-ancestors 'none'",
  "object-src 'none'",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data:",
  "style-src 'self' 'unsafe-inline'",
  "connect-src 'self' https://www.googleapis.com https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://firestore.googleapis.com https://firebasestorage.googleapis.com https://firebaseinstallations.googleapis.com https://firebase.googleapis.com https://apis.google.com https://accounts.google.com https://*.googleapis.com wss://dutch-game.me https://dutch-game.me",
  "frame-src 'self' https://*.google.com https://*.googleusercontent.com https://*.firebaseapp.com",
  "worker-src 'self' blob:",
  "manifest-src 'self'",
  "form-action 'self'",
  "media-src 'self' blob: data: https:",
];

function joinCsp(directives: string[]): string {
  return directives.join('; ');
}

// Google Sign-In via Firebase Auth popup charge apis.google.com/js/api.js,
// accounts.google.com/gsi/client et www.google.com/recaptcha/api.js.
const googleSignInScriptSources =
  'https://www.gstatic.com https://apis.google.com https://accounts.google.com https://www.google.com';

export const strictAdminContentSecurityPolicy = joinCsp([
  ...commonDirectives,
  `script-src 'self' 'unsafe-inline' ${googleSignInScriptSources}`,
]);

export const analyticsAdminContentSecurityPolicy = joinCsp([
  ...commonDirectives,
  `script-src 'self' 'unsafe-inline' ${googleSignInScriptSources} https://cdn.jsdelivr.net`,
]);

export const publicHtmlContentSecurityPolicy = joinCsp([
  ...commonDirectives,
  `script-src 'self' 'unsafe-inline' ${googleSignInScriptSources} https://cdn.jsdelivr.net`,
]);
