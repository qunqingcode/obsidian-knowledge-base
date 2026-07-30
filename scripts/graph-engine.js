(() => {
  "use strict";

  const fs = require("fs");
  const path = require("path");
  const insideObsidian = typeof app !== "undefined" && app && app.vault && app.metadataCache;

  function decodeRequest() {
    if (insideObsidian) return globalThis.__obsidianGraphRequest || {};
    if (!process.argv[2]) throw new Error("Missing graph request.");
    return JSON.parse(Buffer.from(process.argv[2], "base64").toString("utf8"));
  }

  const request = decodeRequest();
  const config = request.config || {};
  const vaultRoot = insideObsidian ? "" : path.resolve(process.argv[3] || config.vaultPath || "");
  const excludedFolders = (config.excludedFolders || [".obsidian/", ".trash/", ".git/"])
    .map(p => normalizePath(p).replace(/^\/+/, "").replace(/\/?$/, "/"));
  const relationshipFields = config.relationshipFields || [
    "Up", "Source", "References", "来源", "参考", "应用于", "衍生自"
  ];
  const frontmatterMapping = Object.assign(
    { domain: "专业", source: "来源", noteType: "笔记类型" },
    config.frontmatterMapping || {}
  );

  function normalizePath(value) {
    return String(value || "").replace(/\\/g, "/").replace(/^\.\//, "");
  }

  function isExcluded(notePath) {
    const normalized = normalizePath(notePath).replace(/^\/+/, "");
    if (!normalized.toLowerCase().endsWith(".md")) return true;
    return excludedFolders.some(prefix => normalized.startsWith(prefix));
  }

  function folderOf(notePath) {
    const normalized = normalizePath(notePath);
    const index = normalized.lastIndexOf("/");
    return index >= 0 ? normalized.substring(0, index) : "(root)";
  }

  function titleOf(notePath) {
    return normalizePath(notePath).split("/").pop().replace(/\.md$/i, "");
  }

  function createGraph(backend) {
    return {
      backend,
      nodes: new Map(),
      outgoing: new Map(),
      incoming: new Map(),
      undirected: new Map(),
      edgeReasons: new Map(),
      unresolved: []
    };
  }

  function ensureNode(graph, notePath, metadata) {
    const normalized = normalizePath(notePath);
    if (!graph.nodes.has(normalized)) {
      graph.nodes.set(normalized, Object.assign({
        path: normalized,
        title: titleOf(normalized),
        size: 0,
        created: 0,
        modified: 0,
        frontmatter: {},
        content: ""
      }, metadata || {}));
    } else if (metadata) {
      Object.assign(graph.nodes.get(normalized), metadata);
    }
    if (!graph.outgoing.has(normalized)) graph.outgoing.set(normalized, new Set());
    if (!graph.incoming.has(normalized)) graph.incoming.set(normalized, new Set());
    if (!graph.undirected.has(normalized)) graph.undirected.set(normalized, new Set());
  }

  function edgeKey(source, target) {
    return `${source}\u0000${target}`;
  }

  function addReason(graph, source, target, reason) {
    const key = edgeKey(source, target);
    if (!graph.edgeReasons.has(key)) graph.edgeReasons.set(key, []);
    const reasons = graph.edgeReasons.get(key);
    const encoded = JSON.stringify(reason);
    if (!reasons.some(item => JSON.stringify(item) === encoded)) reasons.push(reason);
  }

  function addEdge(graph, sourcePath, targetPath, reason) {
    const source = normalizePath(sourcePath);
    const target = normalizePath(targetPath);
    if (!graph.nodes.has(source) || !graph.nodes.has(target) || source === target) return;
    graph.outgoing.get(source).add(target);
    graph.incoming.get(target).add(source);
    graph.undirected.get(source).add(target);
    graph.undirected.get(target).add(source);
    if (reason) addReason(graph, source, target, reason);
  }

  function copyFrontmatter(frontmatter) {
    if (!frontmatter || typeof frontmatter !== "object") return {};
    const result = {};
    for (const [key, value] of Object.entries(frontmatter)) {
      if (key !== "position") result[key] = value;
    }
    return result;
  }

  function relationReason(frontmatter, targetPath) {
    const targetTitle = titleOf(targetPath);
    for (const field of relationshipFields) {
      if (frontmatter[field] == null) continue;
      const values = Array.isArray(frontmatter[field]) ? frontmatter[field] : [frontmatter[field]];
      if (values.some(value => String(value).includes(targetTitle))) {
        return { type: "frontmatter", field };
      }
    }
    return null;
  }

  function buildFromObsidian() {
    const graph = createGraph("obsidian");
    const basePath = app.vault.adapter && app.vault.adapter.basePath
      ? String(app.vault.adapter.basePath)
      : "";

    for (const file of app.vault.getMarkdownFiles()) {
      if (isExcluded(file.path)) continue;
      const cache = app.metadataCache.getFileCache(file);
      let content = "";
      if (basePath) {
        try {
          content = fs.readFileSync(path.join(basePath, file.path), "utf8");
        } catch (_) {
          content = "";
        }
      }
      ensureNode(graph, file.path, {
        title: file.basename,
        size: file.stat.size,
        created: file.stat.ctime,
        modified: file.stat.mtime,
        frontmatter: copyFrontmatter(cache && cache.frontmatter),
        content
      });
    }

    const resolvedLinks = app.metadataCache.resolvedLinks || {};
    for (const [rawSource, targets] of Object.entries(resolvedLinks)) {
      const source = normalizePath(rawSource);
      if (isExcluded(source) || !graph.nodes.has(source)) continue;
      const file = app.vault.getAbstractFileByPath(source);
      const cache = file ? app.metadataCache.getFileCache(file) : null;
      const frontmatter = (graph.nodes.get(source) || {}).frontmatter || {};

      for (const rawTarget of Object.keys(targets || {})) {
        const target = normalizePath(rawTarget);
        if (isExcluded(target) || !graph.nodes.has(target)) continue;
        let reason = relationReason(frontmatter, target);
        if (!reason && cache) {
          const candidates = (cache.links || []).concat(cache.embeds || []);
          const targetTitle = titleOf(target);
          const link = candidates.find(item => {
            const raw = normalizePath(String(item.link || "").split("#")[0]);
            return raw === targetTitle || raw === target.replace(/\.md$/i, "") ||
              target.endsWith(`/${raw}.md`);
          });
          if (link) {
            reason = {
              type: "body",
              line: link.position && link.position.start ? link.position.start.line + 1 : null
            };
          }
        }
        addEdge(graph, source, target, reason || { type: "unknown" });
      }
    }

    const unresolved = app.metadataCache.unresolvedLinks || {};
    for (const [source, targets] of Object.entries(unresolved)) {
      if (isExcluded(source)) continue;
      for (const [target, count] of Object.entries(targets || {})) {
        graph.unresolved.push({ source: normalizePath(source), target, count });
      }
    }
    return graph;
  }

  function walkMarkdown(root) {
    const files = [];
    const stack = [root];
    while (stack.length) {
      const current = stack.pop();
      for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
        const fullPath = path.join(current, entry.name);
        const relative = normalizePath(path.relative(root, fullPath));
        if (entry.isDirectory()) {
          const directoryPrefix = `${relative}/`;
          if (!excludedFolders.some(prefix => directoryPrefix.startsWith(prefix))) stack.push(fullPath);
        } else if (entry.isFile() && relative.toLowerCase().endsWith(".md") && !isExcluded(relative)) {
          files.push({ fullPath, relative });
        }
      }
    }
    return files.sort((a, b) => a.relative.localeCompare(b.relative));
  }

  function parseScalar(value) {
    const trimmed = String(value || "").trim();
    if (!trimmed) return "";
    if (
      (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'"))
    ) {
      return trimmed.slice(1, -1);
    }
    if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
      return trimmed.slice(1, -1).split(",").map(item => parseScalar(item)).filter(Boolean);
    }
    if (/^(true|false)$/i.test(trimmed)) return trimmed.toLowerCase() === "true";
    if (/^-?\d+(?:\.\d+)?$/.test(trimmed)) return Number(trimmed);
    return trimmed;
  }

  function parseFrontmatter(content) {
    const result = { data: {}, endOffset: 0, lineFields: new Map() };
    if (!content.startsWith("---")) return result;
    const lines = content.split(/\r?\n/);
    if (lines[0].trim() !== "---") return result;
    let currentKey = null;
    let offset = lines[0].length + 1;
    for (let index = 1; index < lines.length; index++) {
      const line = lines[index];
      if (line.trim() === "---") {
        result.endOffset = offset + line.length + 1;
        break;
      }
      const keyMatch = line.match(/^([A-Za-z0-9_\-\u0080-\uFFFF]+)\s*:\s*(.*)$/);
      if (keyMatch) {
        currentKey = keyMatch[1];
        const rawValue = keyMatch[2];
        result.data[currentKey] = rawValue.trim() ? parseScalar(rawValue) : [];
        result.lineFields.set(index + 1, currentKey);
      } else {
        const listMatch = line.match(/^\s*-\s*(.+)$/);
        if (listMatch && currentKey) {
          if (!Array.isArray(result.data[currentKey])) result.data[currentKey] = [result.data[currentKey]];
          result.data[currentKey].push(parseScalar(listMatch[1]));
          result.lineFields.set(index + 1, currentKey);
        }
      }
      offset += line.length + 1;
    }
    return result;
  }

  function addIndexValue(map, key, notePath) {
    const normalized = String(key || "").toLowerCase();
    if (!normalized) return;
    if (!map.has(normalized)) map.set(normalized, []);
    map.get(normalized).push(notePath);
  }

  function buildResolver(graph) {
    const exact = new Map();
    const title = new Map();
    const alias = new Map();
    for (const [notePath, metadata] of graph.nodes.entries()) {
      exact.set(notePath.toLowerCase(), notePath);
      exact.set(notePath.replace(/\.md$/i, "").toLowerCase(), notePath);
      addIndexValue(title, titleOf(notePath), notePath);
      const aliases = metadata.frontmatter.aliases || metadata.frontmatter.alias;
      for (const value of (Array.isArray(aliases) ? aliases : aliases ? [aliases] : [])) {
        addIndexValue(alias, value, notePath);
      }
    }
    return { exact, title, alias };
  }

  function resolveLink(rawValue, sourcePath, resolver) {
    let raw = String(rawValue || "").trim();
    try {
      raw = decodeURIComponent(raw);
    } catch (_) {
      // Keep the original malformed value.
    }
    raw = raw.replace(/^<|>$/g, "").replace(/\\/g, "/");
    raw = raw.split("|")[0].split("#")[0].split("^")[0].trim();
    if (!raw || /^(https?:|mailto:|obsidian:)/i.test(raw)) return null;
    raw = raw.replace(/^\/+/, "");
    const withExtension = raw.toLowerCase().endsWith(".md") ? raw : `${raw}.md`;
    const direct = resolver.exact.get(withExtension.toLowerCase()) ||
      resolver.exact.get(raw.toLowerCase());
    if (direct) return direct;

    const sourceFolder = folderOf(sourcePath) === "(root)" ? "" : folderOf(sourcePath);
    const relative = normalizePath(path.posix.normalize(path.posix.join(sourceFolder, withExtension)));
    const relativeMatch = resolver.exact.get(relative.toLowerCase());
    if (relativeMatch) return relativeMatch;

    const base = titleOf(withExtension).toLowerCase();
    const titleCandidates = resolver.title.get(base) || [];
    if (titleCandidates.length === 1) return titleCandidates[0];
    const aliasCandidates = resolver.alias.get(raw.toLowerCase()) || [];
    if (aliasCandidates.length === 1) return aliasCandidates[0];
    if (titleCandidates.length > 1) return titleCandidates.slice().sort()[0];
    return null;
  }

  function fieldAtLine(frontmatterInfo, line) {
    if (!frontmatterInfo.endOffset || !frontmatterInfo.lineFields.size) return null;
    for (let current = line; current >= 1; current--) {
      if (frontmatterInfo.lineFields.has(current)) return frontmatterInfo.lineFields.get(current);
    }
    return null;
  }

  function buildFromFiles() {
    if (!vaultRoot || !fs.existsSync(vaultRoot)) {
      throw new Error(`Vault path does not exist: ${vaultRoot}`);
    }
    const graph = createGraph("files");
    const sourceData = new Map();
    for (const item of walkMarkdown(vaultRoot)) {
      const stat = fs.statSync(item.fullPath);
      const content = fs.readFileSync(item.fullPath, "utf8");
      const frontmatterInfo = parseFrontmatter(content);
      ensureNode(graph, item.relative, {
        size: stat.size,
        created: stat.birthtimeMs || stat.ctimeMs,
        modified: stat.mtimeMs,
        frontmatter: frontmatterInfo.data,
        content
      });
      sourceData.set(item.relative, { content, frontmatterInfo });
    }

    const resolver = buildResolver(graph);
    const wikiPattern = /!?\[\[([^\]]+)\]\]/g;
    const markdownPattern = /(?<!!)\[[^\]]+\]\(([^)]+)\)/g;

    for (const [source, sourceInfo] of sourceData.entries()) {
      const patterns = [
        { regex: wikiPattern, group: 1, markdown: false },
        { regex: markdownPattern, group: 1, markdown: true }
      ];
      for (const patternInfo of patterns) {
        const regex = new RegExp(patternInfo.regex.source, patternInfo.regex.flags);
        let match;
        while ((match = regex.exec(sourceInfo.content)) !== null) {
          const rawTarget = match[patternInfo.group];
          if (patternInfo.markdown &&
              !String(rawTarget).split("#")[0].toLowerCase().endsWith(".md")) continue;
          const target = resolveLink(rawTarget, source, resolver);
          const line = sourceInfo.content.slice(0, match.index).split(/\r?\n/).length;
          if (!target) {
            graph.unresolved.push({ source, target: rawTarget, line, count: 1 });
            continue;
          }
          const field = fieldAtLine(sourceInfo.frontmatterInfo, line);
          const reason = field && relationshipFields.includes(field)
            ? { type: "frontmatter", field, line }
            : { type: "body", line };
          addEdge(graph, source, target, reason);
        }
      }
    }
    return graph;
  }

  function sorted(values) {
    return Array.from(values || []).sort((a, b) => a.localeCompare(b));
  }

  function edgeDescription(graph, source, target) {
    const forward = graph.outgoing.get(source) && graph.outgoing.get(source).has(target);
    const backward = graph.outgoing.get(target) && graph.outgoing.get(target).has(source);
    return {
      from: source,
      to: target,
      direction: forward && backward ? "both" : forward ? "forward" : "backward",
      reasons: []
        .concat(forward ? graph.edgeReasons.get(edgeKey(source, target)) || [] : [])
        .concat(backward ? graph.edgeReasons.get(edgeKey(target, source)) || [] : [])
    };
  }

  function requireNote(graph, notePath, parameterName) {
    const normalized = normalizePath(notePath);
    if (!graph.nodes.has(normalized)) {
      throw new Error(`${parameterName || "note"} not found in vault: ${normalized}`);
    }
    return normalized;
  }

  function queryLinks(graph, notePath, incoming) {
    const note = requireNote(graph, notePath, "note");
    const values = incoming ? graph.incoming.get(note) : graph.outgoing.get(note);
    return {
      note,
      direction: incoming ? "incoming" : "outgoing",
      total: values.size,
      notes: sorted(values)
    };
  }

  function queryNeighbors(graph, notePath, maxHops) {
    const note = requireNote(graph, notePath, "note");
    const depth = Math.max(1, Math.min(5, Number(maxHops) || 2));
    const distance = new Map([[note, 0]]);
    const queue = [note];
    for (let index = 0; index < queue.length; index++) {
      const current = queue[index];
      const hop = distance.get(current);
      if (hop >= depth) continue;
      for (const neighbor of graph.undirected.get(current) || []) {
        if (!distance.has(neighbor)) {
          distance.set(neighbor, hop + 1);
          queue.push(neighbor);
        }
      }
    }
    const byHop = {};
    for (const [current, hop] of distance.entries()) {
      if (current === note) continue;
      if (!byHop[hop]) byHop[hop] = [];
      byHop[hop].push(current);
    }
    for (const key of Object.keys(byHop)) byHop[key].sort();
    const hop1Edges = (byHop[1] || []).slice(0, 50).map(target => edgeDescription(graph, note, target));
    const total = distance.size - 1;
    if (total > 50) {
      let consumed = 0;
      for (let hop = 1; hop <= depth; hop++) {
        const entries = byHop[hop] || [];
        if (consumed + entries.length > 50) {
          byHop[hop] = { count: entries.length, notes: entries.slice(0, Math.max(0, 50 - consumed)) };
        }
        consumed += entries.length;
      }
    }
    return { source: note, maxHops: depth, neighbors: byHop, hop1Edges, total, truncated: total > 50 };
  }

  function queryPath(graph, fromPath, toPath) {
    const from = requireNote(graph, fromPath, "from");
    const to = requireNote(graph, toPath, "to");
    const parent = new Map([[from, null]]);
    const queue = [from];
    for (let index = 0; index < queue.length && !parent.has(to); index++) {
      for (const neighbor of graph.undirected.get(queue[index]) || []) {
        if (!parent.has(neighbor)) {
          parent.set(neighbor, queue[index]);
          queue.push(neighbor);
        }
      }
    }
    if (!parent.has(to)) return { from, to, found: false, path: [], hops: -1, error: "no_path" };
    const resultPath = [];
    for (let current = to; current !== null; current = parent.get(current)) resultPath.unshift(current);
    const edges = [];
    for (let index = 0; index < resultPath.length - 1; index++) {
      edges.push(edgeDescription(graph, resultPath[index], resultPath[index + 1]));
    }
    return { from, to, found: true, path: resultPath, hops: resultPath.length - 1, edges };
  }

  function queryCluster(graph, notePath) {
    const note = requireNote(graph, notePath, "note");
    const component = new Set([note]);
    const stack = [note];
    while (stack.length) {
      const current = stack.pop();
      for (const neighbor of graph.undirected.get(current) || []) {
        if (!component.has(neighbor)) {
          component.add(neighbor);
          stack.push(neighbor);
        }
      }
    }
    const byFolder = {};
    for (const current of sorted(component)) {
      const folder = folderOf(current);
      if (!byFolder[folder]) byFolder[folder] = [];
      byFolder[folder].push(current);
    }
    if (component.size > 500) {
      const folderCounts = {};
      for (const [folder, notes] of Object.entries(byFolder)) folderCounts[folder] = notes.length;
      return { source: note, total: component.size, truncated: true, folderCounts };
    }
    return { source: note, total: component.size, truncated: false, byFolder };
  }

  function queryBridges(graph) {
    const nodes = sorted(graph.nodes.keys());
    const discovery = new Map();
    const low = new Map();
    const bridges = [];
    const articulation = new Set();
    const roots = new Set();
    let timer = 0;

    for (const start of nodes) {
      if (discovery.has(start)) continue;
      roots.add(start);
      discovery.set(start, timer);
      low.set(start, timer++);
      const stack = [{ node: start, parent: null, index: 0, children: 0, neighbors: sorted(graph.undirected.get(start)) }];
      while (stack.length) {
        const frame = stack[stack.length - 1];
        if (frame.index < frame.neighbors.length) {
          const neighbor = frame.neighbors[frame.index++];
          if (!discovery.has(neighbor)) {
            frame.children++;
            discovery.set(neighbor, timer);
            low.set(neighbor, timer++);
            stack.push({
              node: neighbor,
              parent: frame.node,
              index: 0,
              children: 0,
              neighbors: sorted(graph.undirected.get(neighbor))
            });
          } else if (neighbor !== frame.parent) {
            low.set(frame.node, Math.min(low.get(frame.node), discovery.get(neighbor)));
          }
        } else {
          stack.pop();
          if (frame.parent !== null) {
            low.set(frame.parent, Math.min(low.get(frame.parent), low.get(frame.node)));
            if (low.get(frame.node) > discovery.get(frame.parent)) bridges.push([frame.parent, frame.node]);
            if (!roots.has(frame.parent) && low.get(frame.node) >= discovery.get(frame.parent)) {
              articulation.add(frame.parent);
            }
          } else if (frame.children > 1) {
            articulation.add(frame.node);
          }
        }
      }
    }

    const articulationPoints = Array.from(articulation)
      .map(note => ({ note, degree: graph.undirected.get(note).size }))
      .sort((a, b) => b.degree - a.degree || a.note.localeCompare(b.note));
    const bridgesByFolder = {};
    for (const [left, right] of bridges) {
      for (const folder of new Set([folderOf(left), folderOf(right)])) {
        bridgesByFolder[folder] = (bridgesByFolder[folder] || 0) + 1;
      }
    }
    return {
      bridgeEdges: bridges.slice(0, 50),
      totalBridges: bridges.length,
      bridgesByFolder,
      articulationPoints: articulationPoints.slice(0, 30),
      totalArticulationPoints: articulationPoints.length,
      totalNodes: nodes.length
    };
  }

  function queryHubs(graph, topN, folderFilter) {
    const top = Math.max(1, Math.min(100, Number(topN) || 20));
    const folder = normalizePath(folderFilter || "");
    let hubs = Array.from(graph.nodes.keys()).map(note => ({
      note,
      inDegree: graph.incoming.get(note).size,
      outDegree: graph.outgoing.get(note).size,
      total: graph.incoming.get(note).size + graph.outgoing.get(note).size
    }));
    if (folder) hubs = hubs.filter(item => item.note.startsWith(folder));
    hubs.sort((a, b) => b.total - a.total || b.inDegree - a.inDegree || a.note.localeCompare(b.note));
    return { folderFilter: folder || null, topN: top, totalNodes: hubs.length, hubs: hubs.slice(0, top) };
  }

  function selectedFrontmatter(metadata) {
    const source = metadata.frontmatter || {};
    const keys = new Set(["tags", "aliases", ...relationshipFields, ...Object.values(frontmatterMapping)]);
    const selected = {};
    for (const key of keys) if (source[key] != null) selected[key] = source[key];
    return selected;
  }

  function queryOrphans(graph, folderFilter, maxResults) {
    const folder = normalizePath(folderFilter || "");
    const limit = Math.max(1, Math.min(500, Number(maxResults) || 100));
    const orphans = [];
    for (const [note, metadata] of graph.nodes.entries()) {
      if (folder && !note.startsWith(folder)) continue;
      if (graph.outgoing.get(note).size === 0 && graph.incoming.get(note).size === 0) {
        orphans.push({
          path: note,
          size: metadata.size,
          created: metadata.created,
          modified: metadata.modified,
          frontmatter: selectedFrontmatter(metadata)
        });
      }
    }
    orphans.sort((a, b) => b.modified - a.modified || a.path.localeCompare(b.path));
    return { folderFilter: folder || null, total: orphans.length, orphans: orphans.slice(0, limit) };
  }

  function queryRelations(graph, notePath) {
    const note = requireNote(graph, notePath, "note");
    const metadata = graph.nodes.get(note);
    const relations = {};
    for (const field of relationshipFields) {
      if (metadata.frontmatter[field] != null) {
        relations[field] = Array.isArray(metadata.frontmatter[field])
          ? metadata.frontmatter[field]
          : [metadata.frontmatter[field]];
      }
    }
    const inlineRelations = [];
    const inlinePattern = /\[([A-Za-z0-9_\-\u0080-\uFFFF]+)::\s*\[\[([^\]]+)\]\]\]/g;
    let match;
    while ((match = inlinePattern.exec(metadata.content || "")) !== null) {
      inlineRelations.push({ field: match[1], target: match[2] });
    }
    return {
      note,
      frontmatterRelations: relations,
      inlineRelations,
      outgoingLinks: sorted(graph.outgoing.get(note)),
      incomingLinks: sorted(graph.incoming.get(note)),
      totalOutgoing: graph.outgoing.get(note).size,
      totalIncoming: graph.incoming.get(note).size
    };
  }

  function connectedComponents(graph) {
    const visited = new Set();
    const components = [];
    for (const start of sorted(graph.nodes.keys())) {
      if (visited.has(start)) continue;
      const component = [];
      const queue = [start];
      visited.add(start);
      for (let index = 0; index < queue.length; index++) {
        const current = queue[index];
        component.push(current);
        for (const neighbor of graph.undirected.get(current) || []) {
          if (!visited.has(neighbor)) {
            visited.add(neighbor);
            queue.push(neighbor);
          }
        }
      }
      components.push(component);
    }
    components.sort((a, b) => b.length - a.length);
    return components;
  }

  function queryStats(graph) {
    const totalNotes = graph.nodes.size;
    let totalLinks = 0;
    let crossFolderLinks = 0;
    const folderStats = {};
    const monthlyCreation = {};
    const orphanPaths = [];
    const outOnlyNotes = [];

    for (const [note, metadata] of graph.nodes.entries()) {
      const outDegree = graph.outgoing.get(note).size;
      const inDegree = graph.incoming.get(note).size;
      totalLinks += outDegree;
      if (outDegree === 0 && inDegree === 0) orphanPaths.push(note);
      if (outDegree > 0 && inDegree === 0) outOnlyNotes.push(note);
      const folder = folderOf(note);
      if (!folderStats[folder]) folderStats[folder] = { notes: 0, links: 0, orphans: 0 };
      folderStats[folder].notes++;
      folderStats[folder].links += outDegree;
      if (outDegree === 0 && inDegree === 0) folderStats[folder].orphans++;
      if (metadata.created) {
        const date = new Date(metadata.created);
        if (!Number.isNaN(date.getTime())) {
          const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
          monthlyCreation[key] = (monthlyCreation[key] || 0) + 1;
        }
      }
      for (const target of graph.outgoing.get(note)) {
        if (folderOf(target) !== folder) crossFolderLinks++;
      }
    }

    const components = connectedComponents(graph);
    const largestComponent = components.length ? components[0].length : 0;
    return {
      totalNotes,
      totalLinks,
      avgLinksPerNote: Math.round(totalLinks / Math.max(totalNotes, 1) * 100) / 100,
      orphanCount: orphanPaths.length,
      orphanRatio: Math.round(orphanPaths.length / Math.max(totalNotes, 1) * 10000) / 10000,
      componentCount: components.length,
      largestComponent,
      largestComponentRatio: Math.round(largestComponent / Math.max(totalNotes, 1) * 10000) / 10000,
      componentSizes: components.slice(0, 20).map(component => component.length),
      folderStats,
      crossFolderLinks,
      crossFolderRatio: Math.round(crossFolderLinks / Math.max(totalLinks, 1) * 10000) / 10000,
      monthlyCreation: Object.fromEntries(Object.entries(monthlyCreation).sort()),
      outOnlyCount: outOnlyNotes.length,
      outOnlyNotes: outOnlyNotes.sort().slice(0, 50),
      unresolvedCount: graph.unresolved.length
    };
  }

  function profileFor(graph, note) {
    const frontmatter = graph.nodes.get(note).frontmatter || {};
    const tags = Array.isArray(frontmatter.tags)
      ? frontmatter.tags
      : frontmatter.tags ? [frontmatter.tags] : [];
    function first(field) {
      const value = frontmatter[field];
      return String(Array.isArray(value) ? value[0] || "" : value || "").toLowerCase();
    }
    return {
      tags: new Set(tags.map(tag => String(tag).toLowerCase())),
      domain: first(frontmatterMapping.domain),
      source: first(frontmatterMapping.source),
      noteType: first(frontmatterMapping.noteType)
    };
  }

  function querySuggestions(graph, maxSuggestions) {
    const limit = Math.max(1, Math.min(100, Number(maxSuggestions) || 30));
    const orphanNotes = [];
    const linkedNotes = [];
    for (const note of sorted(graph.nodes.keys())) {
      if (graph.undirected.get(note).size === 0) orphanNotes.push(note);
      else linkedNotes.push(note);
    }
    const linkedProfiles = linkedNotes.slice(0, 500).map(note => ({ note, profile: profileFor(graph, note) }));
    const orphanSuggestions = [];
    for (const orphan of orphanNotes.slice(0, 50)) {
      const sourceProfile = profileFor(graph, orphan);
      const candidates = [];
      for (const candidate of linkedProfiles) {
        let score = 0;
        const reasons = [];
        if (sourceProfile.tags.size && candidate.profile.tags.size) {
          const shared = Array.from(sourceProfile.tags).filter(tag => candidate.profile.tags.has(tag));
          if (shared.length) {
            const union = new Set([...sourceProfile.tags, ...candidate.profile.tags]).size;
            score += shared.length / union * 3;
            reasons.push(`tags: [${shared.join(", ")}]`);
          }
        }
        for (const [key, weight] of [["domain", 2], ["source", 2], ["noteType", 1]]) {
          if (sourceProfile[key] && sourceProfile[key] === candidate.profile[key]) {
            score += weight;
            reasons.push(`${key}: ${sourceProfile[key]}`);
          }
        }
        if (score > 0) candidates.push({
          note: candidate.note,
          score: Math.round(score * 100) / 100,
          reasons
        });
      }
      candidates.sort((a, b) => b.score - a.score || a.note.localeCompare(b.note));
      if (candidates.length) orphanSuggestions.push({ orphan, suggestions: candidates.slice(0, 3) });
    }
    orphanSuggestions.sort((a, b) => b.suggestions[0].score - a.suggestions[0].score);

    const eligible = linkedNotes.filter(note => graph.undirected.get(note).size >= 2).slice(0, 500);
    const seen = new Set();
    const missingLinkSuggestions = [];
    for (const note of eligible) {
      const neighbors = graph.undirected.get(note);
      for (const neighbor of neighbors) {
        for (const hop2 of graph.undirected.get(neighbor) || []) {
          if (hop2 === note || neighbors.has(hop2)) continue;
          const pair = note < hop2 ? `${note}\u0000${hop2}` : `${hop2}\u0000${note}`;
          if (seen.has(pair)) continue;
          seen.add(pair);
          const secondNeighbors = graph.undirected.get(hop2) || new Set();
          const common = Array.from(neighbors).filter(value => secondNeighbors.has(value)).length;
          if (common >= 2) {
            const union = new Set([...neighbors, ...secondNeighbors]).size;
            missingLinkSuggestions.push({
              noteA: note,
              noteB: hop2,
              commonNeighbors: common,
              jaccard: Math.round(common / union * 10000) / 10000
            });
          }
        }
      }
    }
    missingLinkSuggestions.sort((a, b) =>
      b.jaccard - a.jaccard || b.commonNeighbors - a.commonNeighbors ||
      a.noteA.localeCompare(b.noteA)
    );
    return {
      orphanSuggestions: orphanSuggestions.slice(0, limit),
      missingLinkSuggestions: missingLinkSuggestions.slice(0, limit),
      totalOrphans: orphanNotes.length,
      scannedOrphans: Math.min(orphanNotes.length, 50),
      totalNodes: graph.nodes.size,
      scannedNodes: Math.min(eligible.length, 500)
    };
  }

  function status(value, greenTest, yellowTest) {
    if (greenTest(value)) return "green";
    if (yellowTest(value)) return "yellow";
    return "red";
  }

  function queryHealth(graph) {
    const stats = queryStats(graph);
    const bridges = queryBridges(graph);
    const suggestions = querySuggestions(graph, request.maxSuggestions || 30);
    const articulationRatio = bridges.totalArticulationPoints / Math.max(stats.totalNotes, 1);
    const outOnlyRatio = stats.outOnlyCount / Math.max(stats.totalNotes, 1);
    const kpis = {
      orphanRatio: {
        value: stats.orphanRatio,
        status: status(stats.orphanRatio, value => value < 0.10, value => value <= 0.25)
      },
      largestComponentRatio: {
        value: stats.largestComponentRatio,
        status: status(stats.largestComponentRatio, value => value > 0.80, value => value >= 0.50)
      },
      avgLinksPerNote: {
        value: stats.avgLinksPerNote,
        status: status(stats.avgLinksPerNote, value => value > 3, value => value >= 1.5)
      },
      crossFolderRatio: {
        value: stats.crossFolderRatio,
        status: status(stats.crossFolderRatio, value => value > 0.20, value => value >= 0.10)
      },
      articulationRatio: {
        value: Math.round(articulationRatio * 10000) / 10000,
        status: status(articulationRatio, value => value < 0.05, value => value <= 0.15)
      },
      outOnlyRatio: {
        value: Math.round(outOnlyRatio * 10000) / 10000,
        status: status(outOnlyRatio, value => value < 0.05, value => value <= 0.15)
      }
    };
    const values = Object.values(kpis).map(item => item.status);
    const red = values.filter(value => value === "red").length;
    const yellow = values.filter(value => value === "yellow").length;
    const grade = red >= 2 ? "needs-attention" : red === 1 || yellow >= 2 ? "room-for-improvement" : "healthy";
    return { grade, kpis, stats, bridges, suggestions };
  }

  function dispatch(graph) {
    const mode = String(request.mode || "").toLowerCase();
    switch (mode) {
      case "links": return queryLinks(graph, request.note, false);
      case "backlinks": return queryLinks(graph, request.note, true);
      case "neighbors": return queryNeighbors(graph, request.note, request.depth);
      case "path": return queryPath(graph, request.from, request.to);
      case "cluster": return queryCluster(graph, request.note);
      case "bridges": return queryBridges(graph);
      case "hubs": return queryHubs(graph, request.top, request.folder);
      case "orphans": return queryOrphans(graph, request.folder, request.maxResults);
      case "relations": return queryRelations(graph, request.note);
      case "stats": return queryStats(graph);
      case "unresolved":
        return { total: graph.unresolved.length, links: graph.unresolved.slice(0, request.maxResults || 100) };
      case "suggest-links": return querySuggestions(graph, request.maxSuggestions);
      case "health": return queryHealth(graph);
      case "report":
        return {
          stats: queryStats(graph),
          hubs: queryHubs(graph, request.top || 10, request.folder),
          bridges: queryBridges(graph),
          orphans: queryOrphans(graph, request.folder, request.maxResults || 100),
          health: queryHealth(graph)
        };
      default: throw new Error(`Unsupported graph mode: ${mode}`);
    }
  }

  const graph = insideObsidian ? buildFromObsidian() : buildFromFiles();
  const result = dispatch(graph);
  result._meta = {
    backend: graph.backend,
    totalNotes: graph.nodes.size,
    unresolvedLinks: graph.unresolved.length
  };
  const json = JSON.stringify(result);
  if (!insideObsidian) process.stdout.write(json);
  return json;
})()
