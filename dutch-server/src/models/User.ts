export interface User {
  id: number;
  username: string;
  email: string | null;
  display_name: string;
  password_hash: string;
  created_at: string;
  updated_at: string;
  last_login_at: string | null;
  is_banned: number;
}

export interface PublicUser {
  id: number;
  username: string;
  displayName: string;
}
