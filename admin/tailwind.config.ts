import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // Mirrors the mobile app's palette (CLAUDE.md). Keeps the
        // admin panel visually close to the user-facing surface.
        primary: "#1565C0",
        navy: "#0D1B3E",
        ink: "#1A1A2E",
        canvas: "#F5F7FA",
        gold: "#C8A951",
        ok: "#2E7D32",
        warn: "#D32F2F",
      },
      fontFamily: {
        sans: ['"Poppins"', "system-ui", "sans-serif"],
      },
    },
  },
  plugins: [],
};

export default config;
