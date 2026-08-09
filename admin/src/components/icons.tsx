/**
 * Inline stroke icons.
 *
 * Hand-rolled rather than an icon package: the console uses about twenty of
 * them, and a dependency would ship a few thousand. They all share one 24×24
 * grid and inherit `currentColor`, so a nav item and a button tint them the
 * same way without any per-icon styling.
 */
type P = { className?: string; size?: number; style?: React.CSSProperties };

function Svg({
  children,
  className,
  size = 18,
  style,
}: P & { children: React.ReactNode }) {
  return (
    <svg
      className={className}
      style={style}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.9}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

export const IconGauge = (p: P) => (
  <Svg {...p}>
    <path d="M12 14a2 2 0 1 0 0-4 2 2 0 0 0 0 4Z" />
    <path d="m13.4 10.6 4.1-4.1" />
    <path d="M20.5 16a9 9 0 1 0-17 0" />
  </Svg>
);

export const IconWrench = (p: P) => (
  <Svg {...p}>
    <path d="M14.7 6.3a4 4 0 0 0 5 5l-9.4 9.4a2.1 2.1 0 0 1-3-3l9.4-9.4Z" />
    <path d="M14.7 6.3 17.5 3.5" />
  </Svg>
);

export const IconStore = (p: P) => (
  <Svg {...p}>
    <path d="M3 9h18l-1.2-4.2A1.5 1.5 0 0 0 18.3 4H5.7a1.5 1.5 0 0 0-1.5 1.1L3 9Z" />
    <path d="M4 9v10a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1V9" />
    <path d="M9 20v-6h6v6" />
  </Svg>
);

export const IconFlag = (p: P) => (
  <Svg {...p}>
    <path d="M4 21V4" />
    <path d="M4 5h11l-1.6 3.2L15 12H4" />
  </Svg>
);

export const IconChat = (p: P) => (
  <Svg {...p}>
    <path d="M20 15a2 2 0 0 1-2 2H8l-4 3V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v9Z" />
  </Svg>
);

export const IconNews = (p: P) => (
  <Svg {...p}>
    <path d="M4 5h13a1 1 0 0 1 1 1v13a1 1 0 0 0 1 1H5a1 1 0 0 1-1-1V5Z" />
    <path d="M18 8h1a1 1 0 0 1 1 1v10" />
    <path d="M7 9h7M7 13h7M7 16h4" />
  </Svg>
);

export const IconCalendar = (p: P) => (
  <Svg {...p}>
    <rect x="3" y="5" width="18" height="16" rx="2" />
    <path d="M3 10h18M8 3v4M16 3v4" />
  </Svg>
);

export const IconBriefcase = (p: P) => (
  <Svg {...p}>
    <rect x="3" y="7" width="18" height="13" rx="2" />
    <path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" />
    <path d="M3 12h18" />
  </Svg>
);

export const IconChurch = (p: P) => (
  <Svg {...p}>
    <path d="M12 2v5M10 4h4" />
    <path d="m12 7 6 4v10H6V11l6-4Z" />
    <path d="M10 21v-5h4v5" />
  </Svg>
);

export const IconShield = (p: P) => (
  <Svg {...p}>
    <path d="M12 3l7 3v6c0 4.4-3 7.9-7 9-4-1.1-7-4.6-7-9V6l7-3Z" />
    <path d="m9 12 2 2 4-4" />
  </Svg>
);

export const IconPlay = (p: P) => (
  <Svg {...p}>
    <rect x="2.5" y="5" width="19" height="14" rx="4" />
    <path d="m10.5 9.2 4.6 2.8-4.6 2.8V9.2Z" fill="currentColor" stroke="none" />
  </Svg>
);

export const IconUsers = (p: P) => (
  <Svg {...p}>
    <path d="M16 20v-1.5a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4V20" />
    <circle cx="9.5" cy="7.5" r="3.5" />
    <path d="M21 20v-1.5a4 4 0 0 0-3-3.9" />
    <path d="M15.5 4.2a3.5 3.5 0 0 1 0 6.6" />
  </Svg>
);

export const IconMegaphone = (p: P) => (
  <Svg {...p}>
    <path d="M4 10v4a1 1 0 0 0 1 1h3l7 4V5L8 9H5a1 1 0 0 0-1 1Z" />
    <path d="M18.5 9.5a3.5 3.5 0 0 1 0 5" />
    <path d="M8 15v4" />
  </Svg>
);

export const IconChart = (p: P) => (
  <Svg {...p}>
    <path d="M4 20V4" />
    <path d="M4 20h16" />
    <path d="M8 17v-5M12.5 17V8M17 17v-7" />
  </Svg>
);

export const IconCompass = (p: P) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="m15.5 8.5-2 5-5 2 2-5 5-2Z" />
  </Svg>
);

export const IconKey = (p: P) => (
  <Svg {...p}>
    <circle cx="8" cy="12" r="4" />
    <path d="M12 12h9M18 12v3M15.5 12v2.4" />
  </Svg>
);

export const IconHistory = (p: P) => (
  <Svg {...p}>
    <path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1" />
    <path d="M3 4v4h4" />
    <path d="M12 8v4.5l3 1.8" />
  </Svg>
);

export const IconSearch = (p: P) => (
  <Svg {...p}>
    <circle cx="11" cy="11" r="6.5" />
    <path d="m16 16 4.5 4.5" />
  </Svg>
);

export const IconRefresh = (p: P) => (
  <Svg {...p}>
    <path d="M20 11a8 8 0 1 0-.7 4" />
    <path d="M20 4v7h-7" />
  </Svg>
);

export const IconCheck = (p: P) => (
  <Svg {...p}>
    <path d="m5 12.5 4.5 4.5L19 7" />
  </Svg>
);

export const IconX = (p: P) => (
  <Svg {...p}>
    <path d="M6 6l12 12M18 6 6 18" />
  </Svg>
);

export const IconAlert = (p: P) => (
  <Svg {...p}>
    <path d="M12 3.5 21 19H3l9-15.5Z" />
    <path d="M12 10v4M12 16.8v.2" />
  </Svg>
);

export const IconInfo = (p: P) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="9" />
    <path d="M12 11v5M12 7.8V8" />
  </Svg>
);

export const IconInbox = (p: P) => (
  <Svg {...p}>
    <path d="M4 13h4l1.5 3h5L16 13h4" />
    <path d="M5.5 5h13l1.5 8v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1v-5l1.5-8Z" />
  </Svg>
);

export const IconMenu = (p: P) => (
  <Svg {...p}>
    <path d="M4 7h16M4 12h16M4 17h16" />
  </Svg>
);

export const IconLogout = (p: P) => (
  <Svg {...p}>
    <path d="M15 5H6a1 1 0 0 0-1 1v12a1 1 0 0 0 1 1h9" />
    <path d="M18 12H10M15.5 8.5 19 12l-3.5 3.5" />
  </Svg>
);

export const IconPower = (p: P) => (
  <Svg {...p}>
    <path d="M12 3v9" />
    <path d="M18.4 6.6a9 9 0 1 1-12.8 0" />
  </Svg>
);

export const IconWhatsApp = (p: P) => (
  <Svg {...p}>
    <path d="M3.5 20.5 5 16.4A8 8 0 1 1 8 19.2l-4.5 1.3Z" />
    <path d="M9 9.5c0 3 2.5 5.5 5.5 5.5.6 0 1-.5 1-1l-1.6-.8-1 1a5.4 5.4 0 0 1-2.2-2.2l1-1L11 9.5c-.5 0-1 .4-1 1" />
  </Svg>
);

export const IconCrown = (p: P) => (
  <Svg {...p}>
    <path d="M4 18h16" />
    <path d="m4 8 3.2 3L12 5l4.8 6L20 8v7H4V8Z" />
  </Svg>
);
