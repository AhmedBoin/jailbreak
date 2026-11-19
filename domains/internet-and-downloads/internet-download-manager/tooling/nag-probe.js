const mod = Process.findModuleByName("IDMan.exe");
const base = mod ? mod.base : null;

function rva(p) {
    try {
        if (base && p.compare(base) >= 0 && p.compare(base.add(mod.size)) < 0)
            return "0x" + p.sub(base).toString(16);
        const m = Process.findModuleByAddress(p);
        return (m ? m.name : "?") + "+0x" + (m ? p.sub(m.base).toString(16) : "?");
    } catch (e) { return "?"; }
}

function bt(ctx) {
    try {
        return Thread.backtrace(ctx, Backtracer.FUZZY).slice(0, 10).map(a => rva(a)).join(" < ");
    } catch (e) { return "?"; }
}

function send_(kind, obj) { send(Object.assign({ kind: kind, ts: Date.now() / 1000 }, obj)); }

function hook(mod_, name, cb) {
    let p = null;
    try { p = Module.getGlobalExportByName(name); } catch (e) { }
    if (p === null && Module.getExportByName) { try { p = Module.getExportByName(mod_, name); } catch (e) { } }
    if (p === null) { send_("missing", { api: name }); return; }
    Interceptor.attach(p, cb);
    send_("hooked", { api: name });
}

function wstr(p, n) { try { return p.isNull() ? null : p.readUtf16String(n || 200); } catch (e) { return null; } }
function astr(p, n) { try { return p.isNull() ? null : p.readCString(n || 200); } catch (e) { return null; } }

const gcw = Module.getGlobalExportByName("GetClassNameW");
const gcwFn = new NativeFunction(gcw, "int", ["pointer", "pointer", "int"]);
const gtw = Module.getGlobalExportByName("GetWindowTextW");
const gtwFn = new NativeFunction(gtw, "int", ["pointer", "pointer", "int"]);

function cls(h) {
    if (h.isNull()) return null;
    const b = Memory.alloc(256);
    gcwFn(h, b, 128);
    return b.readUtf16String();
}
function title(h) {
    if (h.isNull()) return null;
    const b = Memory.alloc(512);
    gtwFn(h, b, 256);
    return b.readUtf16String();
}

hook("user32.dll", "RegisterClassW", {
    onEnter(args) {
        const wc = args[0];
        try {
            const name = wc.add(4 * 9).readPointer();
            send_("regcls", { name: wstr(name, 128), bt: bt(this.context) });
        } catch (e) { }
    }
});
hook("user32.dll", "RegisterClassExW", {
    onEnter(args) {
        const wc = args[0];
        try {
            const name = wc.add(4 * 10).readPointer();
            send_("regclsex", { name: wstr(name, 128), bt: bt(this.context) });
        } catch (e) { }
    }
});

hook("user32.dll", "CreateWindowExW", {
    onEnter(args) {
        this.clsIn = wstr(args[1], 128);
        this.nameIn = wstr(args[2], 128);
        this.style = args[3].toInt32() >>> 0;
        this.ex = args[0].toInt32() >>> 0;
        this.parent = args[8];
    },
    onLeave(ret) {
        const c = this.clsIn || cls(ret);
        const t = this.nameIn || title(ret);
        send_("wnd", { hwnd: ret.toString(), cls: c, name: t, style: "0x" + this.style.toString(16), ex: "0x" + this.ex.toString(16), parent: this.parent.toString(), bt: bt(this.context) });
    }
});

hook("user32.dll", "CreateWindowExA", {
    onEnter(args) { this.clsIn = astr(args[1], 128); this.nameIn = astr(args[2], 128); this.style = args[3].toInt32() >>> 0; },
    onLeave(ret) {
        send_("wndA", { hwnd: ret.toString(), cls: this.clsIn || cls(ret), name: this.nameIn || title(ret), style: "0x" + this.style.toString(16), bt: bt(this.context) });
    }
});

hook("user32.dll", "SetWindowTextW", {
    onEnter(args) { send_("settitle", { hwnd: args[0].toString(), text: wstr(args[1], 200), bt: bt(this.context) }); }
});

hook("user32.dll", "MessageBoxW", {
    onEnter(args) { send_("msgw", { text: wstr(args[1], 400), caption: wstr(args[2], 200), bt: bt(this.context) }); }
});

hook("advapi32.dll", "RegQueryValueExA", {
    onEnter(args) { send_("regqA", { name: astr(args[1], 128), bt: bt(this.context) }); }
});
hook("advapi32.dll", "RegSetValueExA", {
    onEnter(args) { send_("regsA", { name: astr(args[1], 128), type: args[3].toInt32(), bt: bt(this.context) }); }
});
hook("advapi32.dll", "RegQueryValueExW", {
    onEnter(args) { send_("regqW", { name: wstr(args[1], 128), bt: bt(this.context) }); }
});
hook("advapi32.dll", "RegSetValueExW", {
    onEnter(args) { send_("regsW", { name: wstr(args[1], 128), type: args[3].toInt32(), bt: bt(this.context) }); }
});

hook("shell32.dll", "ShellExecuteW", {
    onEnter(args) { send_("shell", { file: wstr(args[1], 300), bt: bt(this.context) }); }
});

function resName(p) {
    const v = p.toInt32();
    if (v > 0 && v < 0x10000) return "#" + v;
    return astr(p, 64) || wstr(p, 64);
}

hook("kernel32.dll", "FindResourceA", {
    onEnter(args) {
        send_("findres", { id: resName(args[1]), type: resName(args[2]), bt: bt(this.context) });
    },
    onLeave(ret) { if (!ret.isNull()) send_("findres-hit", { h: ret.toString() }); }
});

hook("kernel32.dll", "CreateDialogParamA", {
    onEnter(args) { send_("cdlgA", { tpl: args[1].toString(), procRva: rva(args[2]), bt: bt(this.context) }); }
});
hook("kernel32.dll", "CreateDialogParamW", {
    onEnter(args) { send_("cdlgW", { tpl: args[1].toString(), procRva: rva(args[2]), bt: bt(this.context) }); }
});

rpc.exports = { ping() { return "ok"; } };
