# Auth UI Design

**Date:** 2026-05-13
**Branch:** feat/authentication
**Server PR:** KwasiAsante/UtilityBillsServer#13

---

## Overview

Add login, register, and logout UI to the Flutter app to support the new per-user session authentication system on the server. Auth is transparent — the app works normally in dev mode (no users registered on server), and only prompts when the server actually requires it (403 response).

---

## Architecture

### New: `lib/services/auth/auth_service.dart`

`AuthService extends ChangeNotifier` — follows the same pattern as `BillsRepository`, `RentorsRepository`, etc.

**State:**
- `String? token` — current session token (null = not logged in)
- `String? email` — signed-in user's email (for display in avatar popup)
- `bool _unauthorized` — set true when a 403 is received; consumed by `MainTabScreen` listener

**Singleton:** `static final AuthService _instance = AuthService._internal(); factory AuthService() => _instance;` — same pattern as other services.

**Methods:**
- `loadFromPrefs()` — restores token + email from SharedPreferences on app start; calls `ApiService.setAuthToken()`
- `login(String email, String password)` — calls `AuthApiService.login()`, persists token + email, calls `ApiService.setAuthToken()`, notifies listeners; returns error string or null on success
- `register(String email, String password)` — calls `AuthApiService.register()`; on success immediately calls `login()` to auto-authenticate; returns error string or null on success
- `logout()` — calls `AuthApiService.logout()`, clears token + email from memory and SharedPreferences, calls `ApiService.setAuthToken(null)`, notifies listeners
- `notifyUnauthorized()` — sets `_pendingUnauthorized = true`, notifies listeners

**Public getters:**
- `bool get isLoggedIn => token != null`
- `bool get pendingUnauthorized` — `MainTabScreen` listener reads this, then calls `clearUnauthorized()` before navigating
- `clearUnauthorized()` — resets the flag

**SharedPreferences keys:** `AUTH_TOKEN`, `AUTH_EMAIL`

---

### Modified: `LoggingHttpClient` (`lib/services/api/api_service.dart`)

On any response with status code `403`, call `AuthService().notifyUnauthorized()` before returning the response. No other change.

---

### Modified: `MainTabScreen` (`lib/screens/main_tab_screen.dart`)

**App bar avatar:**
- When `AuthService().token != null`: show a `CircleAvatar` with the first letter of the email (deep purple background, white text) as an `IconButton` in the app bar actions
- When not logged in: show nothing (no avatar, no icon)
- Tapping the avatar opens a `PopupMenuButton` with two items:
  1. Email address (disabled, grey — informational)
  2. "Sign out" (red text) — calls `AuthService().logout()`

**Listener:**
- `initState`: `_authService.addListener(_onAuthChanged)`
- `dispose`: `_authService.removeListener(_onAuthChanged)`
- `_onAuthChanged`: if `_authService._unauthorized` is true, reset flag, then `Navigator.push(LoginScreen)` as a full-screen modal (`MaterialPageRoute` with `fullscreenDialog: true`)

---

### Modified: `main.dart`

After `ApiService.configure(...)`, call `await AuthService().loadFromPrefs()`.

---

## New Screens

### `lib/screens/auth/login_screen.dart`

**Stateful widget.** Full-screen modal (pushed via `fullscreenDialog: true`).

**Fields:**
- Email — `TextFormField` with email keyboard, autofill hint
- Password — `TextFormField` with obscured text, autofill hint

**Buttons:**
- "Sign in" — `FilledButton` (full width) — validates form, calls `AuthService().login()`, shows error string below form on failure, pops on success
- "Create account" — outlined `FilledButton` (full width, white background, deep purple border) — pushes `RegisterScreen`

**Error display:** A `Text` widget in red below the buttons, initially empty, populated on failed login.

**Loading state:** buttons disabled + `CircularProgressIndicator` while request in flight.

---

### `lib/screens/auth/register_screen.dart`

**Stateful widget.** Pushed from `LoginScreen` (standard push, not modal).

**Fields:**
- Email — `TextFormField`
- Password — `TextFormField`, obscured, hint "min. 8 characters"

**Buttons:**
- "Create account" — `FilledButton` (full width) — validates, calls `AuthService().register()`, on success pops back to login (which then auto-pops if register auto-logs in)

**Footer link:** "Already have an account? Sign in" — calls `Navigator.pop()`

**Error display:** Same pattern as `LoginScreen`.

**Loading state:** Same pattern as `LoginScreen`.

---

## User Flows

| Trigger | Flow |
|---|---|
| App start, token stored | `loadFromPrefs()` → `ApiService.setAuthToken()` → silent restore |
| App start, no token | Nothing — dev mode works without auth |
| API returns 403 | `notifyUnauthorized()` → listener → push `LoginScreen` (modal) |
| Login success | Token stored → `setAuthToken()` → modal pops |
| Register success | Auto-login → same as login success |
| Sign out | `POST /auth/logout` → clear token → avatar disappears |
| Register → back | `Navigator.pop()` → back to `LoginScreen` |

---

## Files Summary

| File | Change |
|---|---|
| `lib/services/auth/auth_service.dart` | **New** |
| `lib/screens/auth/login_screen.dart` | **New** |
| `lib/screens/auth/register_screen.dart` | **New** |
| `lib/services/api/api_service.dart` | 403 → `notifyUnauthorized()` |
| `lib/screens/main_tab_screen.dart` | Avatar in app bar + auth listener |
| `lib/main.dart` | `AuthService().loadFromPrefs()` on startup |
