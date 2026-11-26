// 打印出来的练习卷写完后，拍照让 Max 检查：先用看图模型把手写作答转写成文字，再对照参考答案逐题批改。
import { ask, see, MaxErr } from "./max";

const arr = (s?: string | null): string[] => { try { return s ? JSON.parse(s) : []; } catch { return []; } };

const SYS = `你是初三阅卷老师 Max。下面是一份练习卷的题目、参考答案，以及学生手写作答的转写（来自照片，可能有识别错误；看不清的就标「看不清」，不要硬判）。
逐题批改，输出格式（中文，公式用 $..$）：
每题一行：「序号｜对 / 错 / 部分对 / 没写 / 看不清｜≤30 字点评（错了说错在哪、该怎么改）」
最后空一行，写「总评：」≤60 字，再写「建议先补：」列 1-2 个考点。`;

export async function checkSheet(env: Env, ids: number[], image: string, allow: () => Promise<boolean>): Promise<{ transcript: string; report: string }> {
	if (!ids.length) throw new MaxErr("没有题目");
	const { results } = await env.DB.prepare(`SELECT id, subject, stem, options, answer, explanation FROM questions WHERE id IN (${ids.map(() => "?").join(",")})`).bind(...ids).all<any>();
	const by = new Map(results.map((q) => [q.id, q]));
	const qs = ids.map((id) => by.get(id)).filter(Boolean);
	if (!qs.length) throw new MaxErr("题目不在了");
	const transcript = await see(env, image, "这是学生做完的练习卷（手写作答）。按题号逐题转写学生写的答案，没写的题写「空」。", allow);
	const list = qs.map((q, i) => `${i + 1}. [${q.subject}] ${String(q.stem).slice(0, 300)}${q.options ? "｜选项：" + arr(q.options).join(" ").slice(0, 200) : ""}｜参考答案：${arr(q.answer).join(" / ").slice(0, 120)}${q.explanation ? "｜要点：" + String(q.explanation).slice(0, 120) : ""}`).join("\n");
	const report = await ask(env, [{ role: "system", content: SYS }, { role: "user", content: `题目与参考答案：\n${list}\n\n学生作答（照片转写）：\n${transcript}` }], { max: 1100, route: "hard", strong: true });
	return { transcript, report };
}
