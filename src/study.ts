// AI 学习台：掌握度地图（纯统计，不花额度）+ AI 学习计划 + 知识点微课（流式）+ 带学习数据的答疑。
// 没接模型时：掌握度和「按最薄弱排的计划」照样能用（计划由规则生成），只有微课、答疑、AI 计划需要模型。
import { ask, askStream, cacheGet, cachePut, MaxErr } from "./max";
import { live } from "./live";
import { today } from "./review";

export type Row = { subject: string; topic: string; n: number; r: number; total: number; wrong: number; mastery: number | null; level: "未练" | "薄弱" | "练习中" | "熟练"; last: string | null };
const LV = { weak: 0.6, good: 0.85 };

/** 各考点掌握度：近 60 天已批改作答的答对率（加 1/2 平滑，少量作答不会一下子 0% 或 100%）+ 题库里还没练的考点 */
export async function masteryRows(db: D1Database): Promise<Row[]> {
	const [att, bank] = await Promise.all([
		db.prepare(`SELECT a.subject, COALESCE(q.topic, a.topic, q.category, '未分类') topic, COUNT(*) n, SUM(a.is_correct = 1) r, MAX(a.created_at) last
			FROM attempts a LEFT JOIN questions q ON q.id = a.question_id
			WHERE a.status = '已判' AND a.created_at > datetime('now', '-60 days') GROUP BY 1, 2`).all<{ subject: string; topic: string; n: number; r: number; last: string }>(),
		db.prepare(`SELECT q.subject, COALESCE(q.topic, q.category, '未分类') topic, COUNT(*) total,
			SUM(EXISTS (SELECT 1 FROM attempts a WHERE a.question_id = q.id AND a.is_correct = 0)) wrong
			FROM questions q WHERE q.status = 'active' AND ${live()} GROUP BY 1, 2`).all<{ subject: string; topic: string; total: number; wrong: number }>(),
	]);
	const m = new Map<string, Row>();
	const get = (subject: string, topic: string) => {
		const k = subject + "\u0001" + topic;
		if (!m.has(k)) m.set(k, { subject, topic, n: 0, r: 0, total: 0, wrong: 0, mastery: null, level: "未练", last: null });
		return m.get(k)!;
	};
	for (const a of att.results) { const x = get(a.subject, a.topic); x.n = a.n; x.r = a.r ?? 0; x.last = a.last; }
	for (const b of bank.results) { const x = get(b.subject, b.topic); x.total = b.total; x.wrong = b.wrong ?? 0; }
	const out = [...m.values()].filter((x) => x.subject);
	for (const x of out) {
		if (!x.n) continue;
		x.mastery = Math.round(((x.r + 1) / (x.n + 2)) * 100);
		x.level = x.mastery < LV.weak * 100 ? "薄弱" : x.mastery < LV.good * 100 || x.n < 3 ? "练习中" : "熟练";
	}
	// 排序：薄弱在前（掌握度低、错题多的更靠前），然后练习中、未练、熟练
	const rank = { 薄弱: 0, 练习中: 1, 未练: 2, 熟练: 3 } as const;
	return out.sort((a, b) => rank[a.level] - rank[b.level] || (a.mastery ?? 50) - (b.mastery ?? 50) || b.wrong - a.wrong);
}

const lineOf = (x: Row) => `${x.subject}/${x.topic}｜${x.n ? `练${x.n}题 对${x.r} 掌握${x.mastery}%` : "没练过"}｜${x.level}${x.wrong ? `｜错题${x.wrong}道` : ""}`;

/** Max 看得到的学习数据（答疑时附上，让回答针对这个学生，而不是泛泛而谈） */
export async function studyDigest(db: D1Database, topic?: string): Promise<string> {
	const rows = await masteryRows(db);
	if (!rows.length) return "（学习数据还是空的：题库没题，也没做过题）";
	const { results: notes } = await db.prepare(`SELECT subject, topic, max_reason, max_note FROM questions WHERE max_note IS NOT NULL AND status IN ('active', 'mastered') ORDER BY max_at DESC LIMIT 10`)
		.all<{ subject: string; topic: string | null; max_reason: string | null; max_note: string }>();
	return ["学生的学习数据（掌握度=近 60 天答对率；越靠前越薄弱）：", ...rows.slice(0, 14).map(lineOf),
		notes.length ? "Max 之前看出的错因：\n" + notes.map((n) => `${n.subject}/${n.topic || "?"}：${n.max_reason ? n.max_reason + "，" : ""}${n.max_note}`).join("\n") : "",
		topic ? `学生正在学：${topic}` : "", "回答要结合这些数据，指出这个学生具体弱在哪；建议练习时给 [[练:科目/考点]] 按钮（考点原样抄上面的）。"].filter(Boolean).join("\n");
}

// ---------- 学习计划 ----------
export type Step = { kind: "learn" | "practice" | "review"; topic: string; why: string; n: number };
export type Plan = { say: string; steps: Step[]; ai: boolean; at?: string };

/** 没有模型时的计划：规则排——最薄弱的先讲后练，再来一个没练过的，最后复习一个熟练的 */
export function rulePlan(rows: Row[]): Plan {
	const weak = rows.filter((r) => r.level === "薄弱").slice(0, 2), mid = rows.filter((r) => r.level === "练习中").slice(0, 1), fresh = rows.filter((r) => r.level === "未练" && r.total).slice(0, 1), good = rows.filter((r) => r.level === "熟练").slice(0, 1);
	const steps: Step[] = [];
	for (const w of weak) steps.push({ kind: "learn", topic: `${w.subject}/${w.topic}`, why: `掌握度 ${w.mastery}%，先把概念弄懂`, n: 0 }, { kind: "practice", topic: `${w.subject}/${w.topic}`, why: "讲完马上练", n: 5 });
	for (const w of mid) steps.push({ kind: "practice", topic: `${w.subject}/${w.topic}`, why: `掌握度 ${w.mastery}%，再巩固一下`, n: 5 });
	for (const w of fresh) steps.push({ kind: "learn", topic: `${w.subject}/${w.topic}`, why: "还没练过，先看微课", n: 0 });
	for (const w of good) steps.push({ kind: "review", topic: `${w.subject}/${w.topic}`, why: "熟练了，隔几天回顾一次防遗忘", n: 3 });
	return { say: steps.length ? "按最薄弱的先来：先讲后练" : "还没有学习数据，先去题库做几道题", steps, ai: false };
}

/** 打开页面时用：今天已经让 AI 排过就用它，没有就给规则计划（都不花额度） */
export async function cachedPlan(db: D1Database, rows: Row[]): Promise<Plan> {
	const hit = await cacheGet(db, "plan:" + today(), 24);
	try { if (hit) return JSON.parse(hit).plan; } catch {}
	return rulePlan(rows);
}

const PLAN_SYS = `你是初三学习规划师。据学生各考点掌握度，排今天的学习计划（这是练习册，没有考试和时限）。
只输出 JSON：{"say":"≤30字总述","steps":[{"kind":"learn|practice|review","topic":"科目/考点（照抄给定的名字，一字不改）","why":"≤20字为什么","n":练几道 1-8，learn 写 0}]}
3-5 步：先补最薄弱的（讲解 learn 后紧跟练习 practice），再穿插一个没练过的，最后一个熟练的 review 防遗忘。`;

export async function plan(env: Env, force: boolean, allow: () => Promise<boolean>): Promise<Plan> {
	const db = env.DB, key = "plan:" + today();
	const rows = await masteryRows(db);
	const sig = rows.slice(0, 14).map((r) => `${r.subject}/${r.topic}:${r.n}:${r.r}`).join(",");
	if (!force) { const hit = await cacheGet(db, key, 6); if (hit) { try { const j = JSON.parse(hit); if (j.sig === sig) return j.plan; } catch {} } }
	if (!rows.length) return rulePlan(rows);
	let out: Plan;
	try {
		if (!(await allow())) throw new MaxErr("今天和 Max 聊得够多了");
		const known = new Map(rows.map((r) => [`${r.subject}/${r.topic}`, r]));
		const text = await ask(env, [{ role: "system", content: PLAN_SYS }, { role: "user", content: `今天 ${today()}\n${rows.slice(0, 14).map(lineOf).join("\n")}` }],
			{ max: 500, route: "hard", ok: (t) => /\{[\s\S]*"steps"/.test(t) });
		const j = JSON.parse(text.match(/\{[\s\S]*\}/)![0]);
		const steps: Step[] = (Array.isArray(j.steps) ? j.steps : []).map((s: any) => ({ kind: ["learn", "practice", "review"].includes(s?.kind) ? s.kind : "practice", topic: String(s?.topic ?? "").trim(),
			why: String(s?.why ?? "").slice(0, 40), n: Math.max(0, Math.min(8, Math.round(Number(s?.n) || 0))) })).filter((s: Step) => known.has(s.topic)).slice(0, 6);
		if (!steps.length) throw new Error("计划里没有合法的考点");
		out = { say: String(j.say ?? "").slice(0, 80), steps: steps.map((s) => ({ ...s, n: s.kind === "learn" ? 0 : s.n || 5 })), ai: true };
	} catch { out = rulePlan(rows); } // 模型不在、额度用完、答得不对：用规则计划，页面照样能用
	out.at = new Date().toISOString();
	await cachePut(db, key, JSON.stringify({ sig, plan: out }));
	return out;
}

// ---------- 微课（流式） ----------
const LESSON_SYS = (subject: string, topic: string, extra: string, again: boolean) => `你是初三名师 Max，给学生讲一节「${subject}·${topic}」的微课，≤450 字，中文。
格式（小标题用 **加粗**，不要用 # ）：
**一句话讲清**：最核心的意思。
**核心知识**：3-5 条，公式 $..$，化学式 $\\ce{..}$。
**一道例题**：题 → 思路 → 答案（一步步）。
**最容易错的 2 点**：${extra || "初三同学常见的错误"}。
**自测**：2 道小题，答案放在最后一行「答案：…」。
${again ? "学生上次没看懂：换一种更直观的讲法，多用生活类比、口诀，把例题拆得更细。\n" : ""}最后单独一行写 [[练:${subject}/${topic}]]。可以偶尔点缀一句很短的法语鼓励（Bravo !、Courage !）。`;

export async function lesson(env: Env, topic: string, again: boolean, allow: () => Promise<boolean>): Promise<{ cached?: string; stream?: ReadableStream<Uint8Array> }> {
	const db = env.DB, [sRaw, ...rest] = topic.split("/"), subject = (sRaw || "").trim().slice(0, 10), tp = rest.join("/").trim().slice(0, 30) || "综合";
	if (!subject) throw new MaxErr("没说是哪一科");
	const rows = await masteryRows(db), me = rows.find((r) => r.subject === subject && r.topic === tp);
	const key = `lesson:${subject}/${tp}:${me?.level ?? "新"}`; // 掌握程度变了就重讲一次
	if (!again) { const hit = await cacheGet(db, key, 24 * 7); if (hit) return { cached: hit }; }
	const { results: notes } = await db.prepare("SELECT max_reason, max_note FROM questions WHERE subject = ? AND topic = ? AND max_note IS NOT NULL ORDER BY max_at DESC LIMIT 4").bind(subject, tp).all<{ max_reason: string | null; max_note: string }>();
	const extra = notes.length ? "这个学生的真实错因：" + notes.map((n) => (n.max_reason ? n.max_reason + "—" : "") + n.max_note).join("；") : "";
	if (!(await allow())) throw new MaxErr("今天和 Max 聊得够多了，明天再来");
	const user = me ? `学生在这个考点：${lineOf(me)}` : "学生还没练过这个考点";
	return { stream: await askStream(env, [{ role: "system", content: LESSON_SYS(subject, tp, extra, again) }, { role: "user", content: user }],
		{ max: 1100, route: "hard", done: again ? undefined : (t) => cachePut(db, key, t) }) };
}
