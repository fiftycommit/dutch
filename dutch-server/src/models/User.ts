export interface User {
  id: string;            // Firebase UID
  username: string;
  email: string | null;
  display_name: string;
  created_at: string;
  updated_at: string;
  last_login_at: string | null;
  is_banned: boolean;
}

export interface PublicUser {
  id: string;            // Firebase UID
  username: string;
  displayName: string;
}
