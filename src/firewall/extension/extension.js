// Firewall Monitor — VS Code extension.
//
// Surfaces:
//   1. Allowlist TreeView — feature / persistent / session tiers from
//      `list-domains.sh --json`; session rows get an inline revoke button.
//   2. Attempted/Denied TreeView — deduped DNS attempts from
//      `list-attempts.sh --json` (count + last-seen + first-seen); each row can be
//      ignored, allowed persistently, or allowed for the session.
//   3. Toast — watches /var/log/firewall-changes.log; on a new DOMAIN_ADDED /
//      IP_ADDED line, shows a warning with a "Revoke" action.
//
// Privileged actions go through the sudoers-allowlisted firewall scripts; config
// edits (ignore/allow lists) are written to the node-writable .firewall/ dir. The
// extension itself never needs root.

const vscode = require("vscode");
const { execFile } = require("child_process");
const fs = require("fs");
const path = require("path");

const LIST_DOMAINS = "/usr/local/bin/list-domains.sh";
const LIST_ATTEMPTS = "/usr/local/bin/list-attempts.sh";
const REVOKE_DOMAIN = "/usr/local/bin/revoke-domain.sh";
const ALLOW_DOMAIN = "/usr/local/bin/allow-domain.sh";
const REFRESH_FIREWALL = "/usr/local/bin/refresh-firewall.sh";
const CHANGES_LOG = "/var/log/firewall-changes.log";
const SESSION_DNS_LOG = "/var/log/firewall-dns.log";
const AUDIT_DNS_LOG = "/var/log/firewall-dns-audit.log";

const TIER_LABELS = {
  feature: "Feature (config)",
  persistent: "Persistent (project)",
  session: "Session (revocable)",
};
const TIER_ORDER = ["session", "persistent", "feature"];

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { timeout: 15000 }, (err, stdout, stderr) => {
      if (err) return reject(new Error(stderr || err.message));
      resolve(stdout);
    });
  });
}

class AllowlistProvider {
  constructor() {
    this._onDidChange = new vscode.EventEmitter();
    this.onDidChangeTreeData = this._onDidChange.event;
  }

  refresh() {
    this._onDidChange.fire();
  }

  getTreeItem(item) {
    return item;
  }

  async getChildren(element) {
    if (!element) {
      if (!fs.existsSync(LIST_DOMAINS)) return []; // feature not (re)installed yet
      let entries;
      try {
        entries = JSON.parse(await run(LIST_DOMAINS, ["--json"]));
      } catch (e) {
        vscode.window.showErrorMessage(`Firewall: failed to read allowlist — ${e.message}`);
        return [];
      }
      this._byTier = { feature: [], persistent: [], session: [] };
      for (const e of entries) {
        if (this._byTier[e.tier]) this._byTier[e.tier].push(e);
      }
      // Always show session + persistent (so their inline "+" add button is
      // available even when empty); feature only when it has entries.
      const tiers = TIER_ORDER.filter((t) => t !== "feature" || this._byTier[t].length);
      return tiers.map((t) => {
        const n = this._byTier[t].length;
        const node = new vscode.TreeItem(
          `${TIER_LABELS[t]}  (${n})`,
          n ? vscode.TreeItemCollapsibleState.Expanded : vscode.TreeItemCollapsibleState.None
        );
        node.contextValue =
          t === "session" ? "group-session" : t === "persistent" ? "group-persistent" : "group";
        node.kind = "tier";
        node.tier = t;
        return node;
      });
    }

    // Feature tier → sub-group by feature name (e.g. claude, core, buildkit).
    if (element.kind === "tier" && element.tier === "feature") {
      const counts = {};
      for (const e of this._byTier.feature) {
        const f = e.feature || "(unknown)";
        counts[f] = (counts[f] || 0) + 1;
      }
      return Object.keys(counts)
        .sort()
        .map((f) => {
          const node = new vscode.TreeItem(
            `${f}  (${counts[f]})`,
            vscode.TreeItemCollapsibleState.Collapsed
          );
          node.contextValue = "group";
          node.kind = "feature";
          node.feature = f;
          node.iconPath = new vscode.ThemeIcon("package");
          return node;
        });
    }

    // Leaves: a feature sub-group's domains, or a non-feature tier's domains.
    let rows;
    if (element.kind === "feature") {
      rows = this._byTier.feature.filter((e) => (e.feature || "(unknown)") === element.feature);
    } else {
      rows = this._byTier[element.tier] || [];
    }
    return rows
      .slice()
      .sort((a, b) => a.value.localeCompare(b.value))
      .map((e) => this._leaf(e));
  }

  _leaf(e) {
    const item = new vscode.TreeItem(e.value, vscode.TreeItemCollapsibleState.None);
    item.contextValue = e.tier; // "session" enables the inline revoke button
    const ips = [...new Set(e.ips || [])];
    item.description = ips.join(", ");
    item.tooltip = ips.length ? `${e.value}\n${ips.join("\n")}` : e.value;
    item.value = e.value;
    item.iconPath = new vscode.ThemeIcon(e.tier === "session" ? "clock" : "globe");
    return item;
  }
}

// ── Attempted / Denied view ───────────────────────────────────────────────────
class AttemptsProvider {
  constructor() {
    this._onDidChange = new vscode.EventEmitter();
    this.onDidChangeTreeData = this._onDidChange.event;
  }

  refresh() {
    this._onDidChange.fire();
  }

  getTreeItem(item) {
    return item;
  }

  async getChildren(element) {
    if (element) return [];
    if (!fs.existsSync(LIST_ATTEMPTS)) return []; // feature not (re)installed yet
    let rows;
    try {
      rows = JSON.parse(await run(LIST_ATTEMPTS, ["--json"]));
    } catch (e) {
      vscode.window.showErrorMessage(`Firewall: failed to read attempts — ${e.message}`);
      return [];
    }
    // Only undecided rows reach here — list-attempts.sh drops anything already
    // allowed (→ Allowlist view) or ignored (→ Ignored view). Every row is
    // actionable: ignore / allow-persistent / allow-session.
    return rows.map((r) => {
      const item = new vscode.TreeItem(r.domain, vscode.TreeItemCollapsibleState.None);
      item.contextValue = "attempt";
      item.value = r.domain;
      const bits = [];
      if (r.count) bits.push(`×${r.count}`);
      if (r.last_seen) bits.push((r.last_seen.split(" ")[1] || r.last_seen));
      item.description = bits.join("  ");
      item.tooltip =
        `${r.domain}\nattempts: ${r.count}\nlast: ${r.last_seen || "—"}\n` +
        `first: ${r.first_seen || "—"}`;
      item.iconPath = new vscode.ThemeIcon("circle-slash");
      return item;
    });
  }
}

async function revoke(target) {
  try {
    await run("sudo", [REVOKE_DOMAIN, target]);
    vscode.window.showInformationMessage(`Firewall: revoked ${target}`);
  } catch (e) {
    vscode.window.showErrorMessage(`Firewall: revoke failed for ${target} — ${e.message}`);
  }
}

// ── Config edits (node-writable .firewall/ dir; no sudo) ──────────────────────
function firewallConfigDir() {
  const ws = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  return ws ? path.join(ws.uri.fsPath, ".devcontainer", ".firewall") : null;
}

// Strip a trailing inline comment + surrounding whitespace from a conf line.
const cleanConf = (l) => l.replace(/#.*/, "").trim();

function appendUnique(file, line) {
  let cur = "";
  try {
    cur = fs.readFileSync(file, "utf8");
  } catch (_) {
    cur = "";
  }
  if (cur.split("\n").some((l) => cleanConf(l) === line.trim())) return false;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.appendFileSync(file, (cur && !cur.endsWith("\n") ? "\n" : "") + line + "\n");
  return true;
}

// Drop the line(s) whose pattern matches `target`; keep comments/blanks.
function removeLine(file, target) {
  let cur;
  try {
    cur = fs.readFileSync(file, "utf8");
  } catch (_) {
    return false;
  }
  const lines = cur.split("\n");
  const kept = lines.filter((l) => cleanConf(l) === "" || cleanConf(l) !== target.trim());
  if (kept.length === lines.length) return false; // nothing matched
  fs.writeFileSync(file, kept.join("\n"));
  return true;
}

// Read non-comment patterns from a .firewall conf file.
function readConfPatterns(file) {
  let cur;
  try {
    cur = fs.readFileSync(file, "utf8");
  } catch (_) {
    return [];
  }
  return [...new Set(cur.split("\n").map(cleanConf).filter((p) => p !== ""))].sort();
}

async function ignoreDomain(domain) {
  const dir = firewallConfigDir();
  if (!dir) return vscode.window.showErrorMessage("Firewall: no workspace folder");
  const parent = domain.split(".").slice(1).join(".");
  const choices = [{ label: domain, description: "exact" }];
  if (parent.includes(".")) choices.push({ label: `*.${parent}`, description: "wildcard" });
  const pick = await vscode.window.showQuickPick(choices, {
    placeHolder: `Ignore which pattern for ${domain}?`,
  });
  if (!pick) return;
  const added = appendUnique(path.join(dir, "ignored-domains.conf"), pick.label);
  vscode.window.showInformationMessage(
    added ? `Firewall: ignoring ${pick.label}` : `Firewall: ${pick.label} already ignored`
  );
}

async function allowPersistent(domain) {
  const dir = firewallConfigDir();
  if (!dir) return vscode.window.showErrorMessage("Firewall: no workspace folder");
  const file = path.join(dir, "allowed-domains.conf");
  appendUnique(file, domain);
  try {
    await run("sudo", [REFRESH_FIREWALL, file]);
    vscode.window.showInformationMessage(`Firewall: ${domain} allowed (persistent)`);
  } catch (e) {
    vscode.window.showErrorMessage(`Firewall: refresh failed — ${e.message}`);
  }
}

// Domains the extension just allowed itself. The command path already shows an
// info toast, so the changes-log watcher must NOT also fire a warning for the
// same allow (allow-domain.sh writes DOMAIN_ADDED/IP_ADDED). One-shot, TTL-guarded
// so a stale entry can't suppress an unrelated later allow of the same name.
const selfAllowed = new Map(); // target -> expiry epoch ms
function markSelfAllowed(target) {
  selfAllowed.set(target, Date.now() + 10000);
}
function wasSelfAllowed(target) {
  const exp = selfAllowed.get(target);
  if (exp === undefined) return false;
  selfAllowed.delete(target); // one-shot
  return Date.now() <= exp;
}

async function allowTemp(domain, ip) {
  const args = ip ? [ALLOW_DOMAIN, domain, ip] : [ALLOW_DOMAIN, domain];
  // Mark BEFORE running: allow-domain.sh writes DOMAIN_ADDED/IP_ADDED to the log
  // before `run` resolves, so the watcher can read that line first. Marking after
  // would lose the race and let a duplicate warning toast through. A stale mark
  // (if the run then fails) just expires harmlessly via its 10s TTL.
  markSelfAllowed(domain);
  try {
    await run("sudo", args);
    vscode.window.showInformationMessage(`Firewall: ${domain} allowed (this session)`);
  } catch (e) {
    const msg = e.message || "";
    // DNS resolution failed — offer to retry with an explicit IP (the script's
    // two-arg form bypasses DNS for hosts-only names like metadata.google.internal).
    if (!ip && /resolve/i.test(msg)) {
      const pick = await vscode.window.showErrorMessage(
        `Firewall: could not resolve ${domain} via DNS`,
        "Specify IP…"
      );
      if (pick === "Specify IP…") {
        const addr = await promptIp(domain);
        if (addr) await allowTemp(domain, addr.trim());
      }
      return;
    }
    vscode.window.showErrorMessage(`Firewall: allow failed — ${msg}`);
  }
}

// Prompt for an explicit IP/CIDR to pair with a hosts-only domain.
function promptIp(domain) {
  return vscode.window.showInputBox({
    prompt: `IP for ${domain} (DNS resolution failed)`,
    placeHolder: "169.254.169.254  or  10.0.0.0/24",
    validateInput: (v) => {
      const s = (v || "").trim();
      if (!s) return "Enter an IP or CIDR";
      return /^[0-9]{1,3}(\.[0-9]{1,3}){3}(\/[0-9]{1,2})?$/.test(s) ? null : "Not an IP/CIDR";
    },
  });
}

// Prompt for a domain/IP to add. Returns undefined if cancelled.
function promptDomain(prompt) {
  return vscode.window.showInputBox({
    prompt,
    placeHolder: "example.com  or  1.2.3.4  or  1.2.3.0/24",
    validateInput: (v) => {
      const s = (v || "").trim();
      if (!s) return "Enter a domain or IP";
      if (/\s/.test(s)) return "No spaces allowed";
      return /^[A-Za-z0-9.*_/-]+$/.test(s) ? null : "Invalid characters";
    },
  });
}

async function addSession() {
  const d = await promptDomain("Allow a domain for this session");
  if (d) await allowTemp(d.trim());
}

async function addPersistent() {
  const d = await promptDomain("Allow a domain persistently (project allowlist)");
  if (d) await allowPersistent(d.trim());
}

// Remove a project-persistent domain: drop from allowed-domains.conf, then
// refresh so it leaves the ipset/hosts. (Feature/session tiers aren't editable
// here — feature is build config, session is revoked via revoke-domain.)
async function removePersistent(domain) {
  const dir = firewallConfigDir();
  if (!dir) return vscode.window.showErrorMessage("Firewall: no workspace folder");
  removeLine(path.join(dir, "allowed-domains.conf"), domain);
  try {
    await run("sudo", [REFRESH_FIREWALL, path.join(dir, "allowed-domains.conf")]);
    vscode.window.showInformationMessage(`Firewall: removed persistent ${domain}`);
  } catch (e) {
    vscode.window.showErrorMessage(`Firewall: refresh failed — ${e.message}`);
  }
}

async function unignore(pattern) {
  const dir = firewallConfigDir();
  if (!dir) return vscode.window.showErrorMessage("Firewall: no workspace folder");
  removeLine(path.join(dir, "ignored-domains.conf"), pattern);
  vscode.window.showInformationMessage(`Firewall: no longer ignoring ${pattern}`);
}

// Move an ignored domain to the persistent allowlist: un-ignore + allow (which
// refreshes). Only offered for non-wildcard entries (a "*.x" can't resolve).
async function allowFromIgnored(pattern) {
  const dir = firewallConfigDir();
  if (!dir) return vscode.window.showErrorMessage("Firewall: no workspace folder");
  removeLine(path.join(dir, "ignored-domains.conf"), pattern);
  await allowPersistent(pattern);
}

// Open one of the firewall logs / project config files via a QuickPick.
async function openFile() {
  const dir = firewallConfigDir();
  const sep = (label) => ({ label, kind: vscode.QuickPickItemKind.Separator });
  const items = [
    sep("Logs (/var/log)"),
    { label: "Firewall changes log", description: "allow / revoke events", file: CHANGES_LOG },
    { label: "DNS session log", description: "attempts this session", file: SESSION_DNS_LOG },
    { label: "DNS audit log", description: "first-seen, deduped", file: AUDIT_DNS_LOG },
  ];
  if (dir) {
    items.push(
      sep("Project config (.firewall)"),
      { label: "allowed-domains.conf", description: "persistent allowlist", file: path.join(dir, "allowed-domains.conf") },
      { label: "ignored-domains.conf", description: "DNS capture filter", file: path.join(dir, "ignored-domains.conf") }
    );
  }
  const pick = await vscode.window.showQuickPick(items, { placeHolder: "Open firewall log or config file" });
  if (!pick || !pick.file) return;
  if (!fs.existsSync(pick.file)) {
    return vscode.window.showWarningMessage(`Firewall: ${pick.file} doesn't exist yet`);
  }
  const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(pick.file));
  await vscode.window.showTextDocument(doc, { preview: false });
}

// ── Ignored view ──────────────────────────────────────────────────────────────
class IgnoredProvider {
  constructor() {
    this._onDidChange = new vscode.EventEmitter();
    this.onDidChangeTreeData = this._onDidChange.event;
  }

  refresh() {
    this._onDidChange.fire();
  }

  getTreeItem(item) {
    return item;
  }

  async getChildren(element) {
    if (element) return [];
    const dir = firewallConfigDir();
    if (!dir) return [];
    return readConfPatterns(path.join(dir, "ignored-domains.conf")).map((p) => {
      const item = new vscode.TreeItem(p, vscode.TreeItemCollapsibleState.None);
      const isWildcard = p.startsWith("*.");
      item.contextValue = isWildcard ? "ignored-wildcard" : "ignored";
      item.value = p;
      if (isWildcard) item.description = "wildcard";
      item.iconPath = new vscode.ThemeIcon("eye-closed");
      return item;
    });
  }
}

// Tail the changes log; surface a toast for each new allow event. Self-heals if
// the watcher drops (log rotated / recreated).
function watchChangesLog(onAllow, disposables) {
  let pos = 0;
  try {
    pos = fs.statSync(CHANGES_LOG).size;
  } catch (_) {
    pos = 0;
  }

  // Serialize reads. fs.watch on a container overlay/bind fs can fire twice for
  // one write and can fire before the data is flushed; without a guard, two
  // concurrent reads grab the same `pos` and re-toast the same line. `pending`
  // re-runs once if the file grew while we were reading.
  let reading = false;
  let pending = false;

  const readNew = () => {
    if (reading) {
      pending = true;
      return;
    }
    reading = true;
    const done = () => {
      reading = false;
      if (pending) {
        pending = false;
        readNew();
      }
    };
    fs.stat(CHANGES_LOG, (err, st) => {
      if (err) return done();
      if (st.size < pos) pos = 0; // truncated/rotated
      if (st.size <= pos) return done();
      const start = pos;
      pos = st.size; // advance BEFORE the async read so a re-fire can't re-read this range
      const stream = fs.createReadStream(CHANGES_LOG, { start, end: st.size - 1 });
      let buf = "";
      stream.on("data", (d) => (buf += d.toString()));
      stream.on("error", done);
      stream.on("end", () => {
        for (const line of buf.split("\n")) {
          const m = line.match(/(DOMAIN_ADDED|IP_ADDED)\s+(\S+)/);
          if (!m) continue;
          const target = m[2];
          if (wasSelfAllowed(target)) continue; // command already showed an info toast
          vscode.window
            .showWarningMessage(`Firewall: ${target} allowed`, "Revoke")
            .then((choice) => {
              if (choice === "Revoke") revoke(target).then(onAllow);
            });
        }
        onAllow();
        done();
      });
    });
  };

  watchFile(CHANGES_LOG, readNew, disposables, 0);
  // Poll fallback: inotify can drop the event for a write, leaving the line
  // unread until the next change. A low-frequency poll guarantees catch-up.
  const iv = setInterval(readNew, 3000);
  disposables.push({ dispose: () => clearInterval(iv) });
}

// Generic self-healing file watcher with optional debounce.
function watchFile(file, cb, disposables, debounceMs = 500) {
  let t = null;
  const trigger = () => {
    if (!debounceMs) return cb();
    clearTimeout(t);
    t = setTimeout(cb, debounceMs);
  };
  const start = () => {
    try {
      const w = fs.watch(file, { persistent: false }, trigger);
      w.on("error", () => setTimeout(start, 2000));
      disposables.push({ dispose: () => w.close() });
    } catch (_) {
      setTimeout(start, 2000); // file not there yet — retry
    }
  };
  start();
}

function activate(context) {
  const allow = new AllowlistProvider();
  const attempts = new AttemptsProvider();
  const ignored = new IgnoredProvider();
  const refreshAll = () => {
    allow.refresh();
    attempts.refresh();
    ignored.refresh();
  };
  const onItem = (fn) => (item) => {
    if (item && item.value) fn(item.value).then(refreshAll);
  };

  context.subscriptions.push(
    vscode.window.registerTreeDataProvider("firewallAllowlist", allow),
    vscode.window.registerTreeDataProvider("firewallAttempts", attempts),
    vscode.window.registerTreeDataProvider("firewallIgnored", ignored),
    vscode.commands.registerCommand("firewall.refresh", () => allow.refresh()),
    vscode.commands.registerCommand("firewall.refreshAttempts", () => attempts.refresh()),
    vscode.commands.registerCommand("firewall.refreshIgnored", () => ignored.refresh()),
    vscode.commands.registerCommand("firewall.revoke", onItem(revoke)),
    vscode.commands.registerCommand("firewall.ignore", onItem(ignoreDomain)),
    vscode.commands.registerCommand("firewall.allowPersistent", onItem(allowPersistent)),
    vscode.commands.registerCommand("firewall.allowTemp", onItem(allowTemp)),
    vscode.commands.registerCommand("firewall.removePersistent", onItem(removePersistent)),
    vscode.commands.registerCommand("firewall.unignore", onItem(unignore)),
    vscode.commands.registerCommand("firewall.allowFromIgnored", onItem(allowFromIgnored)),
    vscode.commands.registerCommand("firewall.openFile", () => openFile()),
    vscode.commands.registerCommand("firewall.addSession", () => addSession().then(refreshAll)),
    vscode.commands.registerCommand("firewall.addPersistent", () => addPersistent().then(refreshAll))
  );

  watchChangesLog(refreshAll, context.subscriptions);
  watchFile(SESSION_DNS_LOG, () => attempts.refresh(), context.subscriptions);

  // Config edits (ours or the user's) reflect immediately in the views. Both
  // files also gate the Attempts inbox (allowed/ignored domains drop out of it),
  // so refresh attempts on either change too — covers external edits the
  // click-path refreshAll wouldn't catch.
  const dir = firewallConfigDir();
  if (dir) {
    watchFile(path.join(dir, "ignored-domains.conf"), () => { ignored.refresh(); attempts.refresh(); }, context.subscriptions);
    watchFile(path.join(dir, "allowed-domains.conf"), () => { allow.refresh(); attempts.refresh(); }, context.subscriptions);
  }
}

function deactivate() {}

module.exports = { activate, deactivate };
