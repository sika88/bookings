// Addresses nobody can claim: they clash with our own routes, hosts or common sense.
export const RESERVED_SLUGS = new Set([
  "app", "www", "api", "admin", "dashboard", "sites", "static", "assets", "cdn", "mail", "email", "smtp", "ftp",
  "ns1", "ns2", "support", "help", "blog", "docs", "status", "billing", "pricing", "about", "contact", "terms",
  "privacy", "login", "signup", "register", "logout", "auth", "account", "accounts", "onboarding", "settings",
  "services", "staff", "bookings", "book", "booking", "b", "pay", "payments", "webhook", "webhooks", "paystack",
  "root", "test", "demo", "staging", "dev", "beta",
]);
