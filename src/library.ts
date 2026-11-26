// 题库全集：所有题永久保存（隐藏、做对、归档的也不删），可搜索、筛选、放回练习；iOS App 用 /api/library/sync 做本地离线副本。
import { live } from "./live";
import { today } from "./review";

const STATE = `CASE WHEN q.status = 'mastered' THEN '已掌握' WHEN q.status = 'done' THEN '已归档' WHEN ${live()} THEN '在用' ELSE '已隐藏' END`;
const STATES = ["在用", "已隐藏", "已掌握", "已归档"];
const arr = (s?: string | null): string[] => { try { return s ? JSON.parse(s) : []; } catch { return []; } };

/** 搜索 / 筛选 / 分页 */
export async function library(db: D1Database, p: { q?: string; subject?: string; state?: string; tag?: string; offset?: number; limit?: number }) {
	const where: string[] = [], bind: unknown[] = [];
	const q = (p.q ?? "").trim().slice(0, 30);
	if (q) { where.push("(q.stem LIKE ? OR q.topic LIKE ? OR q.category LIKE ? OR q.explanation LIKE ?)"); bind.push(...Array(4).fill(`%${q}%`)); }
	if (p.subject) { where.push("q.subject = ?"); bind.push(p.subject); }
	if (p.tag) { where.push("q.tag = ?"); bind.push(p.tag); }
	if (p.state && STATES.includes(p.state)) { where.push(`(${STATE}) = ?`); bind.push(p.state); }
	const w = where.length ? "WHERE " + where.join(" AND ") : "";
	const limit = Math.min(100, Math.max(1, p.limit ?? 40)), offset = Math.max(0, p.offset ?? 0);
	const [rows, total, facets] = await Promise.all([
		db.prepare(`SELECT q.id, q.subject, q.category, q.topic, q.type, q.tag, q.subject || '·' || substr(q.stem, 1, 160) stem, q.created_at, ${STATE} state,
			(SELECT COUNT(*) FROM attempts a WHERE a.question_id = q.id) tries,
			(SELECT COUNT(*) FROM attempts a WHERE a.question_id = q.id AND a.is_correct = 0) wrongs
			FROM questions q ${w} ORDER BY q.id DESC LIMIT ? OFFSET ?`).bind(...bind, limit, offset).all(),
		db.prepare(`SELECT COUNT(*) n FROM questions q ${w}`).bind(...bind).first<{ n: number }>(),
		db.prepare(`SELECT q.subject, ${STATE} state, COUNT(*) n FROM questions q GROUP BY 1, 2`).all<{ subject: string; state: string; n: number }>(),
	]);
	const subjects = [...new Set(facets.results.map((f) => f.subject))].sort();
	const states = Object.fromEntries(STATES.map((s) => [s, facets.results.filter((f) => f.state === s).reduce((t, f) => t + f.n, 0)]));
	return { items: rows.results, total: total?.n ?? 0, subjects, states, offset, limit };
}

/** 放回练习：回到「在用」，今天就能做（间隔复习从第 1 档重新开始） */
export async function restore(db: D1Database, id: number) {
	await db.batch([
		db.prepare("UPDATE questions SET status = 'active', status_at = NULL, created_at = datetime('now'), due = NULL WHERE id = ?").bind(id),
		db.prepare("INSERT INTO review_queue (question_id, next_date, stage) VALUES (?1, ?2, 0) ON CONFLICT(question_id) DO UPDATE SET next_date = ?2, stage = 0").bind(id, today()),
	]);
}

const sha1 = async (s: string) => [...new Uint8Array(await crypto.subtle.digest("SHA-1", new TextEncoder().encode(s)))].map((b) => b.toString(16).padStart(2, "0")).join("");

/** iOS App 的本地副本：全部题（题干、选项、答案、解析、归类）+ 一个内容指纹（ETag）。内容没变，App 带着指纹来问，只回 304 */
export async function snapshot(db: D1Database, inm: string | null): Promise<{ status: 200 | 304; etag: string; body?: string }> {
	const { results } = await db.prepare(`SELECT q.id, q.subject, q.category, q.topic, q.type, q.tag, q.stem, q.options, q.answer, q.explanation, q.status, q.created_at, ${STATE} state,
		(SELECT COUNT(*) FROM attempts a WHERE a.question_id = q.id AND a.is_correct = 0) wrongs,
		(SELECT COUNT(*) FROM attempts a WHERE a.question_id = q.id) tries, q.source
		FROM questions q ORDER BY q.id LIMIT 5000`).all<any>();
	const items = results.map(({ tries, source, ...r }) => {
		const locked = !tries && source !== "原错题"; // 没做过的题：本地副本里也不带答案和解析
		return { ...r, options: arr(r.options), answer: locked ? [] : arr(r.answer), explanation: locked ? null : r.explanation, locked };
	});
	const body = JSON.stringify({ items, at: new Date().toISOString() }), tag = await sha1(JSON.stringify(items));
	const etag = `"${tag}"`;
	if (inm && inm.replace(/^W\//, "") === etag) return { status: 304, etag };
	return { status: 200, etag, body };
}
