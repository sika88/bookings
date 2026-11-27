import Aurora from "@/components/aurora";

export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <Aurora />
      <main className="auth-wrap">{children}</main>
    </>
  );
}
