// 题库全集：永久保存的全部题，搜索 / 按科目、状态筛选 / 放回练习 / 打印所选
(() => {
	const STATES = ["在用", "已隐藏", "已掌握", "已归档"];
	let q = "", subject = "", state = "", offset = 0, total = 0, seq = 0, timer = 0, facets = { subjects: [], states: {} };
	const sel = new Set();
	const tone = { 在用: "due", 已隐藏: "wait", 已掌握: "ok", 已归档: "wait" };

	function chips() {
		$("#lstate").replaceChildren(...["", ...STATES].map((s) => el("button", { className: "chip" + (s === state ? " on" : ""), textContent: s ? `${s} ${facets.states[s] ?? 0}` : "全部状态", onclick: () => { state = s; run(true); } })));
		$("#lsubj").replaceChildren(...["", ...facets.subjects].map((s) => el("button", { className: "chip small" + (s === subject ? " on" : ""), textContent: s || "全部科目", onclick: () => { subject = s; run(true); } })));
	}
	function selBar() {
		$("#lsel").replaceChildren(sel.size ? el("a", { className: "btn small primary", style: "text-decoration:none", href: "/print?ids=" + [...sel].slice(0, 100).join(","), textContent: `打印所选（${sel.size}）` }) : "",
			sel.size ? el("button", { type: "button", className: "btn small", textContent: "清空选择", onclick: () => { sel.clear(); document.querySelectorAll("#list input[type=checkbox]").forEach((c) => (c.checked = false)); selBar(); } }) : "");
	}
	async function run(reset) {
		const my = ++seq;
		if (reset) { offset = 0; $("#list").replaceChildren(); }
		const p = new URLSearchParams({ q, subject, state, offset, limit: 40 });
		const d = await api("/api/library?" + p).catch((e) => (toast(e.message), null));
		if (!d || my !== seq) return;
		facets = d; total = d.total; chips();
		const list = $("#list");
		if (!d.items.length && !offset) list.append(el("p", { className: "mute", style: "padding:14px", textContent: q || subject || state ? "没有符合的题" : "题库还是空的" }));
		for (const it of d.items) list.append(row(it));
		offset += d.items.length;
		$("#more").hidden = offset >= total;
		$("#lsub").textContent = `共 ${total} 题` + (q || subject || state ? "（已筛选）" : "") + " · 所有题永久保存";
		math(list);
	}
	function row(it) {
		const cb = el("input", { type: "checkbox", checked: sel.has(it.id), onclick: (e) => e.stopPropagation(), onchange: () => { cb.checked ? sel.add(it.id) : sel.delete(it.id); selBar(); } });
		const detail = el("div", { className: "detail hide" });
		const item = el("div", { className: "item" }, cb,
			el("div", { className: "body" },
				el("span", { className: "tag", textContent: it.subject }), it.tag ? el("span", { className: "tag ty", textContent: it.tag }) : "", it.topic ? el("span", { className: "tag tp", textContent: it.topic }) : "",
				el("span", { className: "time", textContent: "{clock}" + when(it.created_at) }),
				el("div", { className: "stem", textContent: it.stem.replace(/^[^·]*·/, "") })),
			el("div", { className: "side" }, el("span", { className: "st " + (tone[it.state] || ""), textContent: it.state }), it.tries ? el("span", { className: "mute", style: "font-size:12px", textContent: `做过 ${it.tries}${it.wrongs ? " 错 " + it.wrongs : ""}` }) : ""));
		item.onclick = async () => {
			detail.classList.toggle("hide");
			if (detail.dataset.loaded) return;
			let d; try { d = await api("/api/question/" + it.id); } catch (e) { detail.classList.add("hide"); return toast(e.message); }
			detail.dataset.loaded = "1";
			item.querySelector(".stem").textContent = d.stem.replace(/^[^·]*·/, "");
			if (d.fig && typeof Fig !== "undefined") detail.append(Fig.view(d.fig, "small"));
			if (d.options.length) detail.append(el("div", { className: "mute", textContent: d.options.join("\n"), style: "white-space:pre-wrap" }));
			detail.append(el("div", { className: "ans", textContent: "正确答案：" + (d.answer.join(" / ") || "（无）") }));
			if (d.explanation) detail.append(el("div", { className: "ans", textContent: "解析：" + d.explanation }));
			detail.append(el("div", { className: "row", style: "margin-top:8px" },
				el("a", { className: "btn", href: "/quiz?ids=" + it.id, textContent: "练这题", style: "text-decoration:none" }),
				it.state !== "在用" ? el("button", { className: "btn", textContent: "放回练习", onclick: async (e) => { e.target.disabled = true; await api(`/api/question/${it.id}/restore`, { method: "POST" }).catch((x) => toast(x.message)); toast("已放回，今天的练习里能看到"); run(true); } }) : "",
				el("a", { className: "btn", href: "/print?ids=" + it.id, textContent: "打印", style: "text-decoration:none" }),
				el("button", { className: "btn", textContent: "删除", style: "color:var(--bad)", onclick: async () => { if (await delQuestion(it.id)) run(true); } })));
			math(detail);
		};
		return el("div", { className: "wrapitem" }, item, detail);
	}
	$("#lq").addEventListener("input", (e) => { q = e.target.value; clearTimeout(timer); timer = setTimeout(() => run(true), 300); });
	$("#more").onclick = () => run(false);
	chips(); selBar(); run(true);
})();
