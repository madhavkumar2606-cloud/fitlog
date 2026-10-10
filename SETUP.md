# Setting up FitLog

FitLog works fully offline without any setup. Accounts, friends and the leaderboard need a free
Supabase project.

## 1. Create the Supabase project

1. Sign up at https://supabase.com and create a new project (free plan, region: Mumbai).
2. **SQL Editor → New query**: paste all of `supabase/schema.sql` and press **Run**.
3. **Project Settings → API Keys** (or **Data API**): copy the **Project URL** and the
   **publishable key** (or the legacy **anon public** key). Both are safe to put in the app;
   the security rules in `schema.sql` protect the data.

## 2. Configure sign-in

1. **Authentication → Sign In / Providers → Email**: make sure it is enabled.
   While testing, turn **Confirm email** off. Supabase's built-in email sender only sends
   a few emails per hour.
2. **Authentication → URL Configuration → Redirect URLs**: add
   `com.madhav.fitlog://login-callback`

### Google sign-in (optional)

1. Go to https://console.cloud.google.com, create a project, then
   **APIs & Services → OAuth consent screen**: choose External and fill in the app name
   and your email. Add yourself and your friends as test users (or publish the app).
2. **Credentials → Create credentials → OAuth client ID → Web application**.
   Under **Authorized redirect URIs** add `https://YOUR-PROJECT-ID.supabase.co/auth/v1/callback`.
3. Copy the **Client ID** and **Client secret** into Supabase:
   **Authentication → Sign In / Providers → Google**, then enable it and save.

## 3. Give the keys to the app

**On your laptop:** copy `env.example.json` to `env.json` and fill in your URL and key.
`env.json` is in `.gitignore` so it never gets uploaded. Run with:

```
flutter run --dart-define-from-file=env.json
```

(In VS Code, F5 does this automatically using `.vscode/launch.json`.)

**On GitHub:** go to the repo's **Settings → Secrets and variables → Actions → New repository secret**
and add `SUPABASE_URL` and `SUPABASE_KEY`. The build workflow writes `env.json` from them.

## 4. Optional: permanent signing key

Without this, every GitHub build is signed with a throwaway key, so people must uninstall
before updating (which deletes their on-phone data). Set it up once:

1. In PowerShell (keytool comes with Android Studio):
   ```
   & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Pick a password and remember it. **Back up `upload-keystore.jks` somewhere safe and never
   commit it.** If you lose it, you can never update the app for existing users.
2. Copy it as text:
   ```
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
   ```
3. Add two repository secrets: `KEYSTORE_BASE64` (paste) and `KEYSTORE_PASSWORD`.

## 5. Release

```
git add .
git commit -m "describe the change"
git push
git tag v2.0.0
git push origin v2.0.0
```
