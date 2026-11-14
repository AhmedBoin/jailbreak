// Runtime probe for Internet Download Manager 6.x, 32-bit builds.
// Load through tooling/hook-status.py, which calls the setDispatcher export
// with the file-relative RVA of the status dispatcher before the process is
// resumed. Frida 17 API: module exports are resolved globally, because the
// per-module export helpers moved off the Module namespace.

var base = Process.mainModule.base;
var started = Date.now();

function ts() {
  return ((Date.now() - started) / 1000).toFixed(2);
}

function globalExport(name) {
  try {
    return Module.getGlobalExportByName(name);
  } catch (e) {
    return null;
  }
}

function backtrace(ctx) {
  try {
    return Thread.backtrace(ctx, Backtracer.FUZZY)
      .slice(0, 10)
      .map(function (a) {
        var m = Process.findModuleByAddress(a);
        return m ? m.name + "@" + a.sub(m.base).toString(16) : a.toString();
      })
      .join(" <- ");
  } catch (e) {
    return "bt-fail";
  }
}

function hookExport(name, argIndex, label) {
  var a = globalExport(name);
  if (!a) {
    send({ kind: "missing", api: name });
    return;
  }
  Interceptor.attach(a, {
    onEnter: function (args) {
      var rec = {
        kind: "call",
        ts: ts(),
        api: label || name,
        arg0: args[0] ? args[0].toString() : null,
        bt: backtrace(this.context),
      };
      if (typeof argIndex === "number" && args[argIndex]) {
        rec.code = args[argIndex].toInt32();
      }
      send(rec);
    },
  });
  send({ kind: "hooked", api: label || name });
}

function hookMessageBox() {
  var a = globalExport("MessageBoxW");
  if (!a) {
    send({ kind: "missing", api: "MessageBoxW" });
    return;
  }
  Interceptor.attach(a, {
    onEnter: function (args) {
      function read(p) {
        try {
          return p.isNull() ? null : p.readUtf16String(400);
        } catch (e) {
          return "<unreadable>";
        }
      }
      send({
        kind: "messagebox",
        ts: ts(),
        text: read(args[1]),
        caption: read(args[2]),
        type: args[3].toInt32(),
        bt: backtrace(this.context),
      });
    },
  });
  send({ kind: "hooked", api: "MessageBoxW" });
}

function hookDialog() {
  var a = globalExport("DialogBoxParamW");
  if (!a) {
    send({ kind: "missing", api: "DialogBoxParamW" });
    return;
  }
  Interceptor.attach(a, {
    onEnter: function (args) {
      send({
        kind: "dialog",
        ts: ts(),
        template: args[1].toString(),
        proc: args[3].toString(),
        bt: backtrace(this.context),
      });
    },
  });
  send({ kind: "hooked", api: "DialogBoxParamW" });
}

hookExport("ExitProcess", 0);
hookExport("TerminateProcess", 1);
hookExport("RtlExitUserProcess", 0);
hookExport("PostQuitMessage", 0);
hookMessageBox();
hookDialog();

rpc.exports = {
  setDispatcher: function (rva) {
    var address = base.add(rva);
    Interceptor.attach(address, {
      onEnter: function () {
        send({ kind: "status", ts: ts(), phase: "enter" });
      },
      onLeave: function (retval) {
        send({ kind: "status", ts: ts(), phase: "leave", code: retval.toInt32() });
      },
    });
    send({ kind: "hooked", api: "status_dispatcher@0x" + rva.toString(16) });
  },
  setWrapper: function (rva) {
    var address = base.add(rva);
    Interceptor.attach(address, {
      onEnter: function () {
        send({ kind: "wrapper", ts: ts(), phase: "enter" });
      },
      onLeave: function (retval) {
        send({ kind: "wrapper", ts: ts(), phase: "leave", result: retval.toInt32() });
      },
    });
    send({ kind: "hooked", api: "message_wrapper@0x" + rva.toString(16) });
  },
  base: function () {
    return base.toString();
  },
};

send({ kind: "ready", base: base.toString(), pid: Process.id });
