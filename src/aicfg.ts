// 模型接入配置：密钥在网页「设置」里填，存进 D1（meta 表），不用在 Cloudflare 后台加变量。
// 存在服务器而不是只放浏览器：交卷批改、每天凌晨整理等后台任务没有浏览器在场，也要用得上。
// 支持任何 OpenAI 兼容接口（DeepSeek、通义千问、智谱、Kimi …）；密钥只进不出（读取时只返回尾号）。
// 旧的 Cloudflare 变量 DEEPSEEK_API_KEY 还认（兼容），网页里填的优先。
export type AiCfg = { key: string; base: string; model: string; reasoner: string; name: string; prefer: boolean };

const K = "ai:cfg";
const DEF = { base: "https://api.deepseek.com", model: "deepseek-chat", reasoner: "deepseek-reasoner", name: "DeepSeek" };
let memo: { at: number; v: AiCfg | null } | null = null; // 同一个实例里 20 秒内复用，少查库

export async function aiCfg(env: Env): Promise<AiCfg | null> {
	if (memo && Date.now() - memo.at < 20000) return memo.v;
	let v: AiCfg | null = null;
	try {
		const row = await env.DB.prepare("SELECT v FROM meta WHERE k = ?").bind(K).first<{ v: string }>();
		const j = row?.v ? JSON.parse(row.v) : null;
		if (j?.key) v = { ...DEF, prefer: true, ...j };
	} catch {}
	const legacy = (env as any).DEEPSEEK_API_KEY as string | undefined;
	if (!v && legacy) v = { ...DEF, key: legacy, model: (env as any).DEEPSEEK_MODEL || DEF.model, reasoner: (env as any).DEEPSEEK_REASONER_MODEL || DEF.reasoner, prefer: false };
	memo = { at: Date.now(), v };
	return v;
}
export const chatUrl = (c: AiCfg) => c.base.replace(/\/+$/, "") + "/chat/completions";
export const isDeepSeek = (c: AiCfg) => /(^|\.)deepseek\.com$/i.test(new URL(c.base).hostname);

/** 给网页看的（不含密钥） */
export const publicCfg = (c: AiCfg | null) => (c ? { on: true, name: c.name, base: c.base, model: c.model, reasoner: c.reasoner, prefer: c.prefer, tail: c.key.slice(-4) } : { on: false });

const clip = (s: unknown, n: number) => String(s ?? "").trim().slice(0, n);

/** 保存前先用一句极短的话试通；不通就不保存，原样返回原因 */
export async function saveCfg(env: Env, b: Partial<AiCfg>): Promise<{ ok: true } | { ok: false; error: string }> {
	const old = await aiCfg(env);
	const key = clip(b.key, 300) || (old?.key ?? "");
	if (!key) return { ok: false, error: "请填写密钥" };
	if (!/^[\x21-\x7e]+$/.test(key)) return { ok: false, error: "密钥里有不该有的字符（中文、空格？），重新复制一次" };
	let base = clip(b.base, 200) || old?.base || DEF.base;
	try {
		const u = new URL(base);
		if (u.protocol !== "https:") throw 0;
		base = u.origin + u.pathname.replace(/\/+$/, "");
	} catch { return { ok: false, error: "接口地址要是 https:// 开头的网址" }; }
	const c: AiCfg = { key, base, model: clip(b.model, 80) || DEF.model, reasoner: clip(b.reasoner, 80), name: clip(b.name, 20) || "我的模型", prefer: b.prefer !== false };
	try {
		const r = await fetch(chatUrl(c), { method: "POST", signal: AbortSignal.timeout(15000), headers: { "content-type": "application/json", authorization: "Bearer " + c.key },
			body: JSON.stringify({ model: c.model, messages: [{ role: "user", content: "回复ok" }], max_tokens: 5 }) });
		if (!r.ok) {
			const t = (await r.text()).slice(0, 100);
			return { ok: false, error: r.status === 401 ? "密钥不对（401）" : r.status === 402 ? "余额不足（402）" : r.status === 404 ? "接口地址或模型名不对（404）" : `接口返回 ${r.status}：${t}` };
		}
	} catch (e) { return { ok: false, error: "连不上这个接口：" + String(e).slice(0, 60) }; }
	await env.DB.prepare("INSERT OR REPLACE INTO meta (k, v) VALUES (?, ?)").bind(K, JSON.stringify(c)).run();
	await env.DB.prepare("DELETE FROM max_cache WHERE k IN ('dsping', 'dsbal')").run(); // 状态缓存作废，设置页马上重查
	memo = null;
	return { ok: true };
}

export async function clearCfg(env: Env) {
	await env.DB.prepare("DELETE FROM meta WHERE k = ?").bind(K).run();
	await env.DB.prepare("DELETE FROM max_cache WHERE k IN ('dsping', 'dsbal')").run();
	memo = null;
}
