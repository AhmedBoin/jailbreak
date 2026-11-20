// Log every process launch from IDMan with its command line and caller.
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
        return Thread.backtrace(ctx, Backtracer.FUZZY).slice(0, 12).map(a => rva(a)).join(" < ");
    } catch (e) { return "?"; }
}

function send_(kind, obj) { send(Object.assign({ kind: kind, ts: Date.now() / 1000 }, obj)); }

function hook(name, cb) {
    let p = null;
    try { p = Module.getGlobalExportByName(name); } catch (e) { }
    if (p === null) { send_("missing", { api: name }); return; }
    Interceptor.attach(p, cb);
    send_("hooked", { api: name });
}

function astr(p) { try { return p.isNull() ? null : p.readCString(1024); } catch (e) { return null; } }
function wstr(p) { try { return p.isNull() ? null : p.readUtf16String(1024); } catch (e) { return null; } }

function interesting(s) {
    if (!s) return false;
    const l = s.toLowerCase();
    return l.indexOf("http") >= 0 || l.indexOf("internetdownloadmanager") >= 0 || l.indexOf("idm") >= 0;
}

// CreateProcess(A/W): app name is arg 0, command line arg 1.
hook("CreateProcessA", {
    onEnter(args) {
        const app = astr(args[0]), cmd = astr(args[1]);
        if (interesting(app) || interesting(cmd))
            send_("procA", { app: app, cmd: cmd, bt: bt(this.context) });
    }
});
hook("CreateProcessW", {
    onEnter(args) {
        const app = wstr(args[0]), cmd = wstr(args[1]);
        if (interesting(app) || interesting(cmd))
            send_("procW", { app: app, cmd: cmd, bt: bt(this.context) });
    }
});
hook("CreateProcessInternalW", {
    onEnter(args) {
        const app = wstr(args[0]), cmd = wstr(args[1]);
        if (interesting(app) || interesting(cmd))
            send_("procIW", { app: app, cmd: cmd, bt: bt(this.context) });
    }
});
hook("CreateProcessAsUserW", {
    onEnter(args) {
        const app = wstr(args[1]), cmd = wstr(args[2]);
        if (interesting(app) || interesting(cmd))
            send_("procAUW", { app: app, cmd: cmd, bt: bt(this.context) });
    }
});

hook("ShellExecuteA", {
    onEnter(args) {
        const file = astr(args[1]), params = astr(args[2]);
        send_("shellA", { file: file, params: params, bt: bt(this.context) });
    }
});
hook("ShellExecuteW", {
    onEnter(args) {
        const file = wstr(args[1]), params = wstr(args[2]);
        send_("shellW", { file: file, params: params, bt: bt(this.context) });
    }
});
hook("ShellExecuteExA", {
    onEnter(args) {
        try {
            const sei = args[0];
            const verb = astr(sei.add(0).readPointer());
            const file = astr(sei.add(Process.pointerSize * 1).readPointer());
            const params = astr(sei.add(Process.pointerSize * 2).readPointer());
            send_("shellExA", { verb: verb, file: file, params: params, bt: bt(this.context) });
        } catch (e) { }
    }
});
hook("WinExec", {
    onEnter(args) {
        send_("winexec", { cmd: astr(args[0]), bt: bt(this.context) });
    }
});

rpc.exports = { ping() { return "ok"; } };
