/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,

  // Static export: `npm run build` writes a plain folder of HTML/CSS/JS to
  // `admin/out/` that any static host will serve.
  //
  // This console has no server side at all — every page is a client component
  // talking straight to Supabase, and the security is in the database, not in
  // a Node process. So there is nothing for a server to do, and asking the
  // founder to run one (Vercel, a CLI, a new account) buys nothing.
  //
  // What it buys instead: the existing `admin-web/` console is deployed by
  // dragging a folder onto Netlify. This one now deploys exactly the same
  // way, with the same account and the same muscle memory.
  output: "export",

  // Static hosts serve `/users` as `/users/index.html`. Without this the
  // links work on the first load and 404 on refresh.
  trailingSlash: true,
  // Remote covers (news, events, YouTube thumbnails) are shown with plain
  // <img>, not next/image. The console renders a handful of rows at a time,
  // so the optimiser would buy nothing and would need every Supabase and
  // YouTube host allowlisted before a single thumbnail rendered.
  images: { unoptimized: true },
};

export default nextConfig;
