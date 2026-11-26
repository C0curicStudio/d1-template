// A4 排版：选题 → 版式 → 自动分页成真正的 A4 页面 → 打印 / 存 PDF（iOS App 里走系统 AirPrint 或蓝牙打印机）
(() => {
	const MM = 96 / 25.4, W = 210, H = 297, PAD = 12, GAP = 8;
	const native = window.webkit?.messageHandlers?.maxnote; // iOS App 的桥；浏览器里没有
	const opt = { cols: 1, size: 2, ans: "end", lines: 4, name: true };
	const sel = new Set((new URLSearchParams(location.search).get("ids") || "").split(",").map(Number).filter(Boolean));
	let src = "bank", subject = "", list = [], seq = 0, timer = 0;
	const SRC = [["bank", "题库"], ["wrong", "错题本"], ["mastered", "错题文件夹"]];
	const seg = (id, key, items) => {
		const box = $("#" + id);
		const draw = () => box.replaceChildren(...items.map(([v, t]) => el("button", { type: "button", className: opt[key] === v ? "on" : "", textContent: t, onclick: () => { opt[key] = v; draw(); schedule(); } })));
		draw();
	};
	seg("o-cols", "cols", [[1, "单栏"], [2, "双栏"]]);
	seg("o-size", "size", [[1, "小"], [2, "中"], [3, "大"]]);
	seg("o-ans", "ans", [["none", "不带"], ["inline", "题后"], ["end", "末页答案"]]);
	seg("o-lines", "lines", [[0, "不留"], [3, "3 行"], [5, "5 行"], [8, "8 行"]]);
	$("#title").oninput = $("#o-name").onchange = () => { opt.name = $("#o-name").checked; schedule(); };

	// ---------- 选题 ----------
	function drawSrc() {
		$("#src").replaceChildren(...SRC.map(([k, n]) => el("button", { className: "tab" + (src === k ? " on" : ""), textContent: n, onclick: () => { src = k; subject = ""; loadList(); } })));
	}
	async function loadList() {
		drawSrc();
		const my = ++seq, url = src === "bank" ? "/api/bank" : "/api/wrong?tab=" + (src === "mastered" ? "mastered" : "active");
		const d = await api(url).catch((e) => (toast(e.message), { items: [] }));
		if (my !== seq) return;
		list = d.items;
		drawList();
	}
	function drawList() {
		const subs = [...new Set(list.map((q) => q.subject))];
		if (subject && !subs.includes(subject)) subject = "";
		$("#chips").replaceChildren(...["", ...subs].map((s) => el("button", { className: "chip" + (s === subject ? " on" : ""), textContent: s || "全部", onclick: () => { subject = s; drawList(); } })));
		const shown = list.filter((q) => !subject || q.subject === subject), box = $("#pick");
		box.replaceChildren();
		if (!shown.length) box.append(el("p", { className: "mute", style: "padding:12px", textContent: "这里没有题" }));
		let last = "";
		for (const q of shown) {
			const g = q.subject + " › " + (q.topic || q.category || "未分类");
			if (g !== last) { last = g; box.append(el("div", { className: "pg", textContent: g })); }
			const cb = el("input", { type: "checkbox", checked: sel.has(q.id), onchange: () => { cb.checked ? sel.add(q.id) : sel.delete(q.id); count(); schedule(); } });
			box.append(el("label", {}, cb, el("span", { textContent: q.stem.replace(/^[^·]*·/, "").slice(0, 70) })));
		}
		count();
	}
	const count = () => ($("#cnt").textContent = `已选 ${sel.size} 题`);
	$("#all").onclick = () => { list.filter((q) => !subject || q.subject === subject).forEach((q) => sel.add(q.id)); drawList(); schedule(); };
	$("#none").onclick = () => { sel.clear(); drawList(); schedule(); };

	// ---------- 排版 ----------
	const schedule = () => { clearTimeout(timer); timer = setTimeout(render, 250); };
	const tagOf = (q) => q.tag || "";
	function qBlock(q, n) {
		const body = el("div", { className: "qb" });
		const meta = [q.subject, q.topic || q.category].filter(Boolean).join(" · ");
		body.append(el("div", { className: "qm", textContent: meta }), el("div", { className: "qs", textContent: q.stem }));
		if (q.fig) { const f = typeof Fig !== "undefined" ? Fig.view(q.fig, "small") : ""; if (f) { f.onclick = null; f.title = ""; body.append(f); } }
		if (q.options?.length) body.append(el("div", { className: "qo" + (q.options.every((o) => o.length < 16) ? " two" : "") }, ...q.options.map((o) => el("div", { textContent: o }))));
		const draw = /作图|函数|电路|光路|受力/.test(tagOf(q)), long = q.type === "short" && !draw;
		if (draw) body.append(el("div", { className: "box" }));
		else if (long && opt.lines) for (let i = 0; i < opt.lines; i++) body.append(el("div", { className: "ln" }));
		if (opt.ans === "inline") body.append(ansLine(q));
		return el("div", { className: "q" }, el("div", { className: "qn", textContent: n + "." }), body);
	}
	const ansLine = (q) => el("div", { className: "qa", textContent: "答案：" + (q.answer || []).join(" / ") + (q.explanation ? "　解析：" + q.explanation : "") });
	function aBlock(q, n) {
		return el("div", { className: "q" }, el("div", { className: "qn", textContent: n + "." }), el("div", { className: "qb" }, el("div", { className: "qs", textContent: (q.answer || []).join(" / ") || "（无）" }), q.explanation ? el("div", { className: "qm", style: "font-size:.85em;color:#444", textContent: "解析：" + q.explanation }) : ""));
	}
	function header() {
		const h = el("div", { className: "ph" }, el("h1", { textContent: $("#title").value || "练习" }), el("span", { textContent: opt.name ? "姓名：__________　日期：__________" : new Date().toLocaleDateString("zh-CN") }));
		return h;
	}
	async function render() {
		const my = ++seq, paper = $("#paper");
		const ids = [...sel];
		if (!ids.length) { paper.replaceChildren(el("p", { className: "mute noprint", style: "padding:20px", textContent: "先在上面选题，这里会出现排好版的 A4 页面。" })); return; }
		let items = [];
		for (let i = 0; i < ids.length; i += 50) items.push(...(await api("/api/print?ids=" + ids.slice(i, i + 50).join(","))).items);
		if (my !== seq) return;
		await ready();
		const cls = "s" + opt.size, colW = ((W - 2 * PAD) * MM - (opt.cols - 1) * GAP * MM) / opt.cols;
		const meas = el("div", { id: "meas", className: "sheet " + cls, style: `width:${colW}px;height:auto;padding:0;overflow:visible` });
		document.body.append(meas);
		const blocks = items.map((q, i) => qBlock(q, i + 1));
		blocks.forEach((b) => meas.append(b));
		const ansBlocks = opt.ans === "end" ? items.map((q, i) => aBlock(q, i + 1)) : [];
		ansBlocks.forEach((b) => meas.append(b));
		math(meas);
		await new Promise((r) => setTimeout(r, 120)); // 等公式排完再量高度
		const px = (b) => { const cs = getComputedStyle(b); return b.offsetHeight + parseFloat(cs.marginBottom || 0); };
		const hs = new Map([...blocks, ...ansBlocks].map((b) => [b, px(b)]));
		const pages = [], hd = header();
		const full = (H - 2 * PAD) * MM - 22; // 每页可用高度（留页脚）
		const probe = el("div", { className: "sheet " + cls, style: "height:auto;position:absolute;left:-9999px;visibility:hidden" }, hd.cloneNode(true));
		document.body.append(probe);
		const headH = probe.firstChild.offsetHeight + 4 * MM; probe.remove();
		let page = null, col = 0, used = 0;
		const newPage = (first) => { page = { head: first, cols: Array.from({ length: opt.cols }, () => []), room: first ? full - headH : full }; pages.push(page); col = 0; used = 0; };
		const put = (b) => {
			const h = hs.get(b) ?? 0;
			if (used + h > page.room && used > 0) { if (++col >= opt.cols) newPage(false); used = 0; }
			page.cols[col].push(b); used += h;
		};
		newPage(true);
		blocks.forEach(put);
		if (ansBlocks.length) { newPage(false); const sec = el("div", { className: "sec", textContent: "参考答案与解析" }); hs.set(sec, 36); put(sec); ansBlocks.forEach(put); }
		const sheets = pages.map((p, i) => {
			const s = el("div", { className: "sheet " + cls });
			if (p.head) s.append(hd.cloneNode(true));
			s.append(el("div", { className: "cols" }, ...p.cols.map((c) => el("div", { className: "col" }, ...c))), el("div", { className: "pf", textContent: `${i + 1} / ${pages.length}` }));
			return s;
		});
		meas.remove();
		paper.replaceChildren(...sheets);
		fit();
		$("#hint").textContent = `共 ${items.length} 题，${pages.length} 页 A4。`;
	}
	const ready = async () => { for (let i = 0; i < 40 && !(window.renderMathInElement && typeof Fig !== "undefined"); i++) await new Promise((r) => setTimeout(r, 100)); };
	// 手机屏幕比 A4 窄：整体缩放预览（打印时不缩放）
	function fit() {
		const p = $("#paper"), k = Math.min(1, (innerWidth - 0) / (W * MM));
		p.style.zoom = k < 1 ? String(k) : "";
	}
	addEventListener("resize", fit);

	// ---------- 打印 ----------
	const acts = $("#acts");
	acts.append(el("button", { type: "button", className: "btn primary", textContent: native ? "打印（AirPrint）" : "打印 / 存为 PDF", onclick: () => {
		if (!sel.size) return toast("先选题");
		native ? native.postMessage({ type: "print" }) : window.print();
	} }));
	if (native) acts.append(el("button", { type: "button", className: "btn", textContent: "蓝牙打印机", onclick: () => {
		if (!sel.size) return toast("先选题");
		native.postMessage({ type: "bluetooth", sheets: document.querySelectorAll("#paper .sheet").length });
	} }));
	$("#hint").textContent = native ? "" : "提示：在 iPhone 上安装 MAX NOTE App 后，这里可以直接走 AirPrint 或蓝牙打印机。";

	drawSrc();
	loadList();
	if (sel.size) render(); else schedule();
})();
