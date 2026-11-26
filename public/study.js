(() => {
// AI 学习台：掌握度地图 + AI 计划 + 知识点微课（流式）+ 带学习数据的答疑。
// 打开页面不花额度（掌握度、规则计划都是本地算的）；点「学」「问」「AI 重排」才用模型。
const LS = (k) => { try { return localStorage.getItem(k); } catch { return null; } };
const prefs = (() => { try { return JSON.parse(LS("max_prefs") || "{}"); } catch { return {}; } })();
let data = null, topic = "", busy = false;
const LV = { 薄弱: "bad", 练习中: "mid", 熟练: "ok", 未练: "new" };
const practice = (t, n) => "/quiz?topic=" + encodeURIComponent(t) + (n ? "&n=" + n : "");
const kindName = { learn: "讲解", practice: "练习", review: "回顾" };

// 读流：边收边排版（Max.render：加粗、公式、练题按钮）
async function stream(url, body, box) {
	const r = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
	if (r.status === 401) { location.href = "/login"; throw new Error("未登录"); }
	if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || "出错了（" + r.status + "）");
	const rd = r.body.getReader(), dec = new TextDecoder();
	let t = "";
	for (;;) {
		const { done, value } = await rd.read();
		if (done) break;
		t += dec.decode(value, { stream: true });
		Max.render(box, t, false);
	}
	t += dec.decode();
	Max.render(box, t, true);
	return t;
}

// ---------- 顶部 + 计划 ----------
function renderTop() {
	const weak = data.rows.filter((r) => r.level === "薄弱").length, acc = data.n ? Math.round((data.right / data.n) * 100) : null;
	$("#stsub").textContent = data.n ? `近 60 天练了 ${data.n} 题，正确率 ${acc}%，${weak ? weak + " 个薄弱考点" : "没有薄弱考点"} · ` : "还没有做题记录 · ";
	$("#stsub").append(el("span", { textContent: data.ai.on ? `AI：${data.ai.name}` : "AI：用 Cloudflare 免费额度（设置里可接入自己的模型）" }));
}
function renderPlan() {
	const p = data.plan, box = $("#plan");
	box.replaceChildren(el("h2", {}, icon("max"), el("span", { textContent: " 今日学习计划" }), el("span", { className: "maxtag", style: "margin-left:8px", textContent: p.ai ? "AI 排的" : "按薄弱度排的" })),
		el("p", { textContent: p.say || "还没有数据，先去做几道题" }),
		...p.steps.map((s, i) => {
			const [sub, tp] = [s.topic.split("/")[0], s.topic.split("/").slice(1).join("/")];
			return el("div", { className: "pstep" },
				el("span", { className: "tag " + s.kind, textContent: `${i + 1} ${kindName[s.kind]}` }),
				el("div", { className: "pbody" }, el("b", { textContent: `${sub} › ${tp}` }), el("div", { className: "mute", textContent: s.why })),
				s.kind === "learn" ? el("button", { type: "button", className: "btn small", textContent: "学这个", onclick: () => learn(s.topic) })
					: el("a", { className: "btn small", href: practice(s.topic, s.n), textContent: `练 ${s.n} 题`, style: "text-decoration:none" }));
		}),
		el("div", { className: "row" }, el("button", { type: "button", className: "btn small", textContent: "↻ 让 AI 重新排", onclick: async (e) => {
			const b = e.currentTarget; b.disabled = true; b.textContent = "AI 排计划中…";
			try { data.plan = await api("/api/study/plan", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ force: true }) }); renderPlan(); }
			catch (err) { toast(err.message); b.disabled = false; b.textContent = "↻ 让 AI 重新排"; }
		} })));
}

// ---------- 掌握度地图 ----------
function renderMap() {
	const box = $("#map");
	if (!data.rows.length) return box.replaceChildren(el("p", { className: "mute", textContent: "题库还是空的：拍照上传错题，或让 Claude 出题后，这里会出现你的掌握度地图。" }));
	const subs = [...new Set(data.rows.map((r) => r.subject))];
	box.replaceChildren(...subs.map((s) => {
		const rows = data.rows.filter((r) => r.subject === s), open = rows.slice(0, 6), rest = rows.slice(6);
		const row = (r) => el("div", { className: "mprow" },
			el("div", { className: "mpname" }, el("b", { textContent: r.topic }), el("span", { className: "mute", textContent: r.n ? `${r.n} 题 · ${r.mastery}%` : `${r.total} 题未练` }), el("span", { className: "lv " + LV[r.level], textContent: r.level })),
			el("div", { className: "mpbar" }, el("i", { className: LV[r.level], style: `width:${r.mastery ?? 0}%` })),
			el("div", { className: "mpact" }, el("button", { type: "button", className: "btn small", textContent: "学", onclick: () => learn(r.subject + "/" + r.topic) }),
				el("a", { className: "btn small", href: practice(r.subject + "/" + r.topic, 5), textContent: "练", style: "text-decoration:none" })));
		const more = rest.length ? el("details", {}, el("summary", { className: "mute", textContent: `还有 ${rest.length} 个考点` }), ...rest.map(row)) : "";
		return el("div", { className: "card" }, el("h2", { textContent: s }), ...open.map(row), more);
	}));
}

// ---------- 微课 ----------
async function learn(t, again = false) {
	if (busy) return toast("AI 还在回答上一个，稍等");
	busy = true; topic = t;
	const box = $("#lesson"), body = el("div", { className: "lbody mb assistant", textContent: "AI 正在备课…" });
	box.hidden = false;
	box.replaceChildren(el("h2", {}, icon("max"), el("span", { textContent: " " + t.replace("/", " › ") })), body);
	box.scrollIntoView({ behavior: "smooth", block: "start" });
	try {
		await stream("/api/study/lesson", { topic: t, again }, body);
		box.append(el("div", { className: "row" },
			el("button", { type: "button", className: "btn small", textContent: "没懂，换种讲法", onclick: () => learn(t, true) }),
			el("a", { className: "btn small primary", href: practice(t, 5), textContent: "去练 5 题", style: "text-decoration:none" }),
			el("button", { type: "button", className: "btn small", textContent: "问 AI 助教", onclick: () => { $("#q").focus({ preventScroll: false }); $("#chatnote").textContent = "正在学：" + t.replace("/", " › "); } })));
	} catch (e) { body.textContent = e.message; }
	finally { busy = false; }
}

// ---------- 答疑 ----------
const hist = [], tg = { deep: false, web: false };
for (const [id, k] of [["#tdeep", "deep"], ["#tweb", "web"]]) $(id).onclick = (e) => { tg[k] = !tg[k]; e.currentTarget.classList.toggle("on", tg[k]); };
async function ask(text) {
	text = (text ?? $("#q").value).trim();
	if (!text || busy) return;
	busy = true; $("#q").value = ""; $("#send").disabled = true;
	hist.push({ role: "user", content: text });
	const log = $("#log"), me = el("div", { className: "mb user", textContent: text }), ai = el("div", { className: "mb assistant", textContent: "思考中…" });
	log.append(me, ai);
	ai.scrollIntoView({ block: "nearest" });
	try {
		const t = await stream("/api/max/chat", { messages: hist.slice(-6), ctx: { study: true, topic, len: prefs.len || "l", pref: prefs.pref || "auto", deep: tg.deep, web: tg.web } }, ai);
		hist.push({ role: "assistant", content: t });
	} catch (e) { ai.textContent = e.message; hist.pop(); }
	finally { busy = false; $("#send").disabled = false; }
}
$("#send").onclick = () => ask();
$("#q").addEventListener("keydown", (e) => { if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); ask(); } });
$("#log").addEventListener("click", (e) => { const d = e.target.closest("button[data-do]"); if (d) Max.act(d); });
$("#chips").replaceChildren(...["我现在最该先补哪块？", "用一个例子讲讲我最薄弱的考点", "我总是犯哪类错？怎么改？"].map((t) => el("button", { type: "button", className: "chip", textContent: t, onclick: () => ask(t) })));

async function load() {
	data = await api("/api/study");
	renderTop(); renderPlan(); renderMap();
}
load().catch((e) => { $("#stsub").textContent = "加载失败：" + e.message; });
addEventListener("max:changed", () => load().catch(() => {}));
autoRefresh(() => load().catch(() => {}));
})();
