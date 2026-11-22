# Astro Starter Kit: Minimal

```sh
npm create astro@latest -- --template minimal
```

> 🧑‍🚀 **Seasoned astronaut?** Delete this file. Have fun!

## 🚀 Project Structure

Inside of your Astro project, you'll see the following folders and files:

```text
/
├── public/
├── src/
│   └── pages/
│       └── index.astro
└── package.json
```

Astro looks for `.astro` or `.md` files in the `src/pages/` directory. Each page is exposed as a route based on its file name.

There's nothing special about `src/components/`, but that's where we like to put any Astro/React/Vue/Svelte/Preact components.

Any static assets, like images, can be placed in the `public/` directory.

## 🧞 Commands

All commands are run from the root of the project, from a terminal:

| Command                   | Action                                           |
| :------------------------ | :----------------------------------------------- |
| `npm install`             | Installs dependencies                            |
| `npm run dev`             | Starts local dev server at `localhost:4321`      |
| `npm run build`           | Build your production site to `./dist/`          |
| `npm run preview`         | Preview your build locally, before deploying     |
| `npm run astro ...`       | Run CLI commands like `astro add`, `astro check` |
| `npm run astro -- --help` | Get help using the Astro CLI                     |

## Supabase

1. Copy `.env.example` to `.env` in the project root.
2. Set `PUBLIC_SUPABASE_URL` and `PUBLIC_SUPABASE_PUBLISHABLE_KEY` to the values from your Supabase project's API settings.
3. Use `getSupabaseClient()` from `src/lib/supabase.ts` to access the configured client.

The Books page reads `id`, `created_at`, `title`, `author`, `price`, `condition`, `description`, `image_url`, and `sold` from `public.books`. The publishable key is intended for browser use; never put a secret or service-role key in a `PUBLIC_` variable.

### Admin dashboard

The `/admin` page uses Supabase email/password authentication and checks `public.is_admin()` before showing the management interface. Database RLS remains the security boundary for all book changes; hiding the dashboard alone does not grant or protect access.

Before using it:

1. Apply `supabase/migrations/20261122140000_admin_books_security.sql` in the Supabase SQL Editor. It creates the admin allowlist and authorization function, preserves the existing `public.books` columns and data, and applies bucket-scoped `books-images` policies.
2. Create the administrator account in Supabase Authentication. Public sign-up is not exposed by the website.
3. Allowlist that account by running this in the SQL Editor, replacing the example email:

   ```sql
   insert into public.admin_users (user_id)
   select id from auth.users where email = 'admin@example.com'
   on conflict do nothing;
   ```

The migration makes book covers publicly readable because they appear in the public shop, while restricting uploads, updates, and deletes to allowlisted admins. Do not use a Supabase secret or service-role key in the site.

## Cloudflare Pages

This project builds as a static Astro site; no Cloudflare adapter is needed. In Cloudflare, import the existing GitHub repository and use:

- Framework preset: Astro
- Production branch: `main`
- Build command: `npm run build`
- Build output directory: `dist`
- Node.js build version: `22.23.4` (or newer, matching the `engines` requirement in `package.json`)

In the Pages project's **Settings > Environment variables**, add these build variables for both Production and Preview:

- `PUBLIC_SUPABASE_URL`
- `PUBLIC_SUPABASE_PUBLISHABLE_KEY`

Astro reads these during the build and includes them in the browser app. The Supabase URL and publishable key are public values; never configure a Supabase secret or service-role key under a `PUBLIC_` name or expose one in this site.

## 👀 Want to learn more?

Feel free to check [our documentation](https://docs.astro.build) or jump into our [Discord server](https://astro.build/chat).
