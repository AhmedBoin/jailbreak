// Calls the IDM trial-nag thread procedure (RVA 0x74610) so the nag window can
// be observed on demand, then reports every top-level window.
const mod = Process.findModuleByName("IDMan.exe");
const base = mod.base;

function rva(p) {
    try {
        const m = Process.findModuleByAddress(p);
        return m ? m.name + "+0x" + p.sub(m.base).toString(16) : "?";
    } catch (e) { return "?"; }
}

const gcw = Module.getGlobalExportByName("GetClassNameW");
const gcwFn = new NativeFunction(gcw, "int", ["pointer", "pointer", "int"]);
const gtw = Module.getGlobalExportByName("GetWindowTextW");
const gtwFn = new NativeFunction(gtw, "int", ["pointer", "pointer", "int"]);

function winfo(h) {
    if (h.isNull()) return null;
    const cb = Memory.alloc(256), tb = Memory.alloc(512);
    gcwFn(h, cb, 128); gtwFn(h, tb, 256);
    return { hwnd: h.toString(), cls: cb.readUtf16String(), title: tb.readUtf16String() };
}

function enumTop() {
    const out = [];
    const ea = Module.getGlobalExportByName("EnumWindows");
    const cb = new NativeCallback(function (h, l) {
        const w = winfo(h);
        if (w && (w.cls || w.title)) out.push(w);
        return 1;
    }, "int", ["pointer", "pointer"]);
    const en = new NativeFunction(ea, "int", ["pointer", "pointer"]);
    en(cb, ptr(0));
    return out;
}

function snapshotDump(tag) {
    send({ kind: "snapshot", tag: tag, wins: enumTop() });
}

rpc.exports = {
    trigger() {
        const createThread = new NativeFunction(Module.getGlobalExportByName("CreateThread"),
            "pointer", ["pointer", "pointer", "pointer", "pointer", "uint32", "pointer"]);
        const tid = Memory.alloc(4);
        const h = createThread(ptr(0), ptr(0), base.add(0x74610), ptr(0), 0, tid);
        send({ kind: "spawned", thread: h.toString(), tid: tid.readU32() });
        return h.toString();
    },
    // Call MFC's AfxBeginThread wrapper from inside the GUI thread so the new
    // thread gets a proper MFC module state, exactly like the app does itself.
    triggerMfc() {
        const spawn = new NativeFunction(base.add(0x25B617), "pointer",
            ["pointer", "pointer", "int", "uint", "uint", "pointer"]);
        let fired = false;
        const fire = () => {
            if (fired) return;
            fired = true;
            setImmediate(() => {
                try {
                    listener.detach();
                    const t = spawn(base.add(0x74610), ptr(0), 0, 0, 0, ptr(0));
                    send({ kind: "mfc-spawned", thread: t.toString() });
                } catch (e) {
                    send({ kind: "mfc-error", error: String(e) });
                }
            });
        };
        const name = Process.platform === "windows" ? "PeekMessageA" : "PeekMessageW";
        const pm = Module.getGlobalExportByName(name);
        const listener = Interceptor.attach(pm, { onEnter() { fire(); } });
        return "armed";
    },
    snap() { snapshotDump("manual"); return "ok"; }
};
