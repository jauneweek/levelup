import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { TabBar } from "@/components/tab-bar";
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
      <div className="mx-auto w-full max-w-xl flex-1 px-4 pb-28 pt-5">
        {children}
      </div>
      <TabBar pendingCount={day?.pendingCount ?? 0} />
    </>
  );
}
