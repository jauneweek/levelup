import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { TabBar } from "@/components/tab-bar";
import { TopBar } from "@/components/top-bar";
import { getDayState } from "@/lib/quests";

export default async function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const day = await getDayState();

  return (
    <>
      <TopBar />
      {/* La barre du haut est fixe : on réserve sa hauteur (safe-area + ~50px). */}
      <div
        className="mx-auto w-full max-w-xl flex-1 px-4 pb-28"
        style={{ paddingTop: "calc(env(safe-area-inset-top) + 62px)" }}
      >
        {children}
      </div>
      <TabBar pendingCount={day?.pendingCount ?? 0} />
    </>
  );
}
