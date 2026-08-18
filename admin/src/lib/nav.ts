import type { Role } from "./session";
import {
  IconBriefcase,
  IconCalendar,
  IconChart,
  IconChat,
  IconChurch,
  IconCompass,
  IconFlag,
  IconGauge,
  IconHistory,
  IconKey,
  IconMegaphone,
  IconNews,
  IconPlay,
  IconShield,
  IconStore,
  IconUsers,
  IconWrench,
} from "@/components/icons";

export type NavItem = {
  href: string;
  label: string;
  icon: (p: { className?: string; size?: number }) => JSX.Element;
  group: string;
  /** Minimum role that can see the item at all. */
  min: Role;
  /** Key into the badge map, when the item should carry a pending count. */
  badge?: "sellers" | "reports" | "feedback" | "news" | "events" | "jobs" | "claims";
};

/**
 * The console's whole surface, in one list.
 *
 * Ordered by how the work actually arrives: what needs attention today, then
 * the review queues, then the people, then the numbers, then the controls
 * you touch rarely and deliberately. Maintenance sits last with staff and the
 * audit log rather than up top — it is not a daily task, and a switch that
 * turns the entire app off should not live one slip away from the overview.
 */
export const NAV: NavItem[] = [
  { href: "/", label: "Overview", icon: IconGauge, group: "Today", min: "viewer" },

  { href: "/reports", label: "Reports", icon: IconFlag, group: "Queues", min: "moderator", badge: "reports" },
  { href: "/feedback", label: "Feedback", icon: IconChat, group: "Queues", min: "moderator", badge: "feedback" },
  { href: "/sellers", label: "Sellers", icon: IconStore, group: "Queues", min: "moderator", badge: "sellers" },
  { href: "/news", label: "Advent News", icon: IconNews, group: "Queues", min: "moderator", badge: "news" },
  { href: "/events", label: "Events", icon: IconCalendar, group: "Queues", min: "moderator", badge: "events" },
  { href: "/jobs", label: "Jobs", icon: IconBriefcase, group: "Queues", min: "moderator", badge: "jobs" },
  { href: "/church-claims", label: "Church claims", icon: IconChurch, group: "Queues", min: "moderator", badge: "claims" },

  { href: "/church-admins", label: "Church admins", icon: IconShield, group: "People", min: "moderator" },
  { href: "/users", label: "Members", icon: IconUsers, group: "People", min: "moderator" },
  { href: "/watch", label: "Watch channels", icon: IconPlay, group: "People", min: "moderator" },

  { href: "/analytics", label: "Analytics", icon: IconChart, group: "Insight", min: "viewer" },
  { href: "/insights", label: "Why they join & leave", icon: IconCompass, group: "Insight", min: "manager" },

  { href: "/broadcast", label: "Broadcast", icon: IconMegaphone, group: "Controls", min: "owner" },
  { href: "/maintenance", label: "Maintenance", icon: IconWrench, group: "Controls", min: "owner" },
  { href: "/staff", label: "Staff & roles", icon: IconKey, group: "Controls", min: "owner" },
  { href: "/audit", label: "Audit log", icon: IconHistory, group: "Controls", min: "manager" },
];

export const NAV_GROUPS = ["Today", "Queues", "People", "Insight", "Controls"] as const;

/** Page title/subtitle for the top bar, keyed by route. */
export const PAGE_META: Record<string, { title: string; sub?: string }> = {
  "/": { title: "Overview", sub: "What needs your attention today." },
  "/reports": { title: "Reports", sub: "Reported content and accounts." },
  "/feedback": { title: "Feedback", sub: "Messages from members — your reply lands in their notifications." },
  "/sellers": { title: "Sellers", sub: "Storefronts waiting to go live on the marketplace." },
  "/news": { title: "Advent News", sub: "Member-submitted stories awaiting review." },
  "/events": { title: "Events", sub: "Member-submitted events awaiting review." },
  "/jobs": { title: "Jobs", sub: "Member-submitted jobs awaiting review." },
  "/church-claims": { title: "Church claims", sub: "Members applying to manage a church." },
  "/church-admins": { title: "Church admins", sub: "Everyone who can already post as a church." },
  "/users": { title: "Members", sub: "Search the membership, notify or ban." },
  "/watch": { title: "Watch channels", sub: "What feeds the Watch tab." },
  "/analytics": { title: "Analytics", sub: "How Adventist Super App is actually being used." },
  "/insights": { title: "Why they join & leave", sub: "Signup survey and account-deletion reasons." },
  "/broadcast": { title: "Broadcast", sub: "Send a notice to every member, or one province." },
  "/maintenance": { title: "Maintenance", sub: "Take the whole app offline, and bring it back." },
  "/staff": { title: "Staff & roles", sub: "Who can work in this console, and how much they can do." },
  "/audit": { title: "Audit log", sub: "Every action taken from this console." },
};
