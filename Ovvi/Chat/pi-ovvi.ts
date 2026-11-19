// @ts-nocheck
import { appendFileSync, mkdirSync, statSync } from "node:fs";
import { dirname } from "node:path";

export default function (pi) {
	pi.registerFlag("ovvi", { type: "string", description: "Ovvi: the state file to append to" });
	let ui = false; // only a TUI session reports
	let path;
	const write = (line) => {
		const file = pi.getFlag("ovvi");
		// The folder too: Ovvi sweeps side files untouched for 30 days, and empty folders.
		if (ui && file) try {
			mkdirSync(dirname(file), { recursive: true, mode: 0o700 });
			appendFileSync(file, JSON.stringify(line) + "\n", { mode: 0o600 });
		} catch {}
	};
	// What still wakes pi after its turn, as pi-herd (its agents' watches) and pi-bash-bg (its background jobs)
	// count it: 0 while pi works. Ovvi's chat says "Waiting on …" then, not Working.
	const waiting = { agents: 0, jobs: 0 };
	const wait = (kind) => (data) => {
		const count = data?.waiting ?? 0;
		if (count === waiting[kind]) return;
		waiting[kind] = count;
		write({ type: "waiting", ...waiting });
	};
	pi.events.on("herd:update", wait("agents"));
	pi.events.on("bash-bg:update", wait("jobs"));
	pi.on("session_start", (_event, ctx) => {
		ui = ctx.mode === "tui";
		path = ctx.sessionManager.getSessionFile();
		write({ type: "session", path });
		// Always: a count that came ahead of this (another extension's session_start ran first) was not written,
		// and a reload (/new, /resume, /fork, /reload) starts again at 0, over a count the file still holds.
		write({ type: "waiting", ...waiting });
	});
	// /tree writes nothing to the transcript: the new leaf, and the transcript's size at the move (entries after it
	// grow from that leaf).
	pi.on("session_tree", (event) => {
		let at = 0;
		try { at = statSync(path).size; } catch {}
		write({ type: "tree", leaf: event.newLeafId ?? null, at });
	});
	// herdr's pi integration hears another extension's dialog only from this event: its state is then blocked, and it
	// refuses agent.prompt meanwhile.
	pi.on("ui_prompt_start", (event) => {
		pi.events.emit("herdr:blocked", { active: true, label: event.title ?? event.kind });
	});
	pi.on("ui_prompt_end", () => pi.events.emit("herdr:blocked", { active: false }));
}
