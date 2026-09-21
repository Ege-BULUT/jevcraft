'use client';
import { useEffect, useRef, useState } from 'react';
import { browserDb } from '@/lib/db';

type Message = { id: number; at: string; name: string; body: string };
const NAME_KEY = 'jevcraft.chat.name';

export function Chat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const nameInput = useRef<HTMLInputElement>(null); // uncontrolled: filled from localStorage after mount
  const [body, setBody] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const list = useRef<HTMLDivElement>(null);

  useEffect(() => {
    try { if (nameInput.current) nameInput.current.value = localStorage.getItem(NAME_KEY) ?? ''; } catch { /* private mode: just ask again */ }
    const db = browserDb();
    db.from('jc_chat').select('id, at, name, body').order('at', { ascending: false }).limit(100)
      .then(({ data }) => setMessages(((data ?? []) as Message[]).reverse()));
    const ch = db.channel('chat').on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'jc_chat' },
      ({ new: m }) => setMessages((ms) => [...ms.filter((x) => x.id !== (m as Message).id), m as Message].slice(-200))).subscribe();
    return () => { db.removeChannel(ch); };
  }, []);

  useEffect(() => { list.current?.scrollTo({ top: list.current.scrollHeight }); }, [messages]);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    const name = nameInput.current?.value.trim() ?? '';
    if (!name) { setError('Pick a name first.'); return; }
    if (!body.trim()) return;
    setSending(true); setError(null);
    try { localStorage.setItem(NAME_KEY, name); } catch { /* ignore */ }
    const r = await fetch('/api/chat', { method: 'POST', body: JSON.stringify({ name, body }) }).catch(() => null);
    const j = await r?.json().catch(() => ({}));
    if (r?.ok) setBody(''); else setError(j?.error ?? 'Could not post; try again.');
    setSending(false);
  }

  return (
    <section className="flex h-[420px] flex-col rounded-2xl border border-white/10 bg-black/40">
      <h2 className="border-b border-white/10 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-zinc-400">Live chat</h2>
      <div ref={list} className="flex-1 space-y-1.5 overflow-y-auto px-4 py-3 text-sm">
        {messages.length === 0 && <p className="text-zinc-500">No messages yet. Say hi to Jev.</p>}
        {messages.map((m) => (
          <p key={m.id} className="break-words">
            <span className="mr-2 font-mono text-[11px] text-zinc-500">{new Date(m.at).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Istanbul' })}</span>
            <span className="font-semibold text-lime-300">{m.name}</span>
            <span className="text-zinc-200">: {m.body}</span>
          </p>
        ))}
      </div>
      <form onSubmit={send} className="flex flex-wrap gap-2 border-t border-white/10 p-3">
        <input ref={nameInput} maxLength={24} placeholder="Your name" aria-label="Your name"
          className="w-32 rounded-lg bg-white/10 px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-lime-400" />
        <input value={body} onChange={(e) => setBody(e.target.value)} maxLength={280} placeholder="Say something…" aria-label="Message"
          className="min-w-0 flex-1 rounded-lg bg-white/10 px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-lime-400" />
        <button disabled={sending || !body.trim()} className="rounded-lg bg-lime-400 px-4 py-2 text-sm font-bold text-black disabled:opacity-40">Send</button>
        {error && <p className="w-full text-xs text-red-300">{error}</p>}
      </form>
    </section>
  );
}
