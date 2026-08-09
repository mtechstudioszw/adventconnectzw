/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Remote covers (news, events, YouTube thumbnails) are shown with plain
  // <img>, not next/image. The console renders a handful of rows at a time,
  // so the optimiser would buy nothing and would need every Supabase and
  // YouTube host allowlisted before a single thumbnail rendered.
  images: { unoptimized: true },
};

export default nextConfig;
