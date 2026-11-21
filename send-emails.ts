// Supabase Edge Function "send-emails": sends queued emails through abv.bg (smtp.abv.bg:465)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info" };
const U = Deno.env.get("SMTP_USER")!, SITE = (Deno.env.get("SITE_URL") || "").replace(/\/$/, "");
const D: any = {
  bg: { confirm: "Часът ви е записан", r12: "Напомняне: часът ви е след 12 часа", r2: "Напомняне: часът ви е след 2 часа", moved: "Часът ви е преместен", cancel: "Часът ви е отменен", svc: "Услуга", when: "Кога", note: "Часът е ориентировъчен, възможно е леко разминаване.", link: "Отмяна или промяна на часа", hi: "Здравейте", addr: "бул. „Захари Стоянов“, 8011 Бургас" },
  en: { confirm: "Your appointment is booked", r12: "Reminder: your appointment is in 12 hours", r2: "Reminder: your appointment is in 2 hours", moved: "Your appointment was moved", cancel: "Your appointment was cancelled", svc: "Service", when: "When", note: "Times are approximate; small delays are possible.", link: "Cancel or change your appointment", hi: "Hello", addr: "Zahari Stoyanov Blvd, 8011 Burgas" },
};
const S: any = { staff_new: "Нов час", staff_cancel: "Отменен час", staff_move: "Преместен час" };
const fd = (d: string) => d.split("-").reverse().join(".");
const esc = (s: string) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
function compose(kind: string, b: any) {
  const when = `${fd(b.day)} ${String(b.slot).slice(0, 5)}`, sv = b.lang == "en" ? b.services.name_en : b.services.name_bg;
  if (kind.startsWith("staff_")) {
    const t = `${S[kind]}: ${b.name}, ${when}`;
    return { subject: `${t} (Impas TT)`, html: `<p><b>${S[kind]}</b></p><p>${esc(b.name)}, ${esc(b.phone)}<br>${esc(b.services.name_bg)}<br>${when}<br>${esc(b.car || "")} ${esc(b.comment || "")}</p>` };
  }
  const d = D[b.lang == "en" ? "en" : "bg"], link = `${SITE}/?t=${b.token}`;
  const sub = `${d[kind]}: ${when} – Impas TT`;
  const cta = kind == "cancel" ? "" : `<p><a href="${link}">${d.link}</a></p><p style="color:#666">${d.note}</p>`;
  return { subject: sub, html: `<div style="font-family:Arial,sans-serif;max-width:520px"><h2>${d[kind]}</h2><p>${d.hi}, ${esc(b.name)}.</p><p><b>${d.svc}:</b> ${esc(sv)}<br><b>${d.when}:</b> ${when}<br>${d.addr}<br>+359 88 710 2219</p>${cta}</div>` };
}
Deno.serve(async (req) => {
  if (req.method == "OPTIONS") return new Response("ok", { headers: cors });
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: rows } = await sb.rpc("claim_emails");
  if (!rows?.length) return new Response(JSON.stringify({ sent: 0 }), { headers: cors });
  const smtp = new SMTPClient({ connection: { hostname: "smtp.abv.bg", port: 465, tls: true, auth: { username: U, password: Deno.env.get("SMTP_PASS")! } } });
  let sent = 0;
  for (const r of rows) {
    try {
      const { data: b } = await sb.from("bookings").select("*,services(name_bg,name_en)").eq("id", r.booking_id).single();
      const live = b && (b.status == "booked" || ["cancel", "staff_cancel"].includes(r.kind));
      if (live) { const m = compose(r.kind, b); await smtp.send({ from: `Impas TT <${U}>`, to: r.to_email, replyTo: U, subject: m.subject, content: "auto", html: m.html }); sent++; }
      await sb.from("email_queue").update({ sent_at: new Date().toISOString(), error: null }).eq("id", r.id);
    } catch (e) { await sb.from("email_queue").update({ error: String(e).slice(0, 300) }).eq("id", r.id); }
  }
  await smtp.close();
  return new Response(JSON.stringify({ sent }), { headers: cors });
});
