#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const COMPATIBLE = "compatible";
const INCOMPATIBLE = "incompatible";
const COMPATIBLE_PROPERTY_NAME = "compatibleOptionalField";
const COMPATIBLE_PROPERTY_DESCRIPTION = "Randomized compatible response field";

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const repoRoot = path.resolve(args.repoRoot);
  const metadataPath = path.join(
    repoRoot,
    ".bcc-temp",
    "openapi-bcc",
    "last-run.json",
  );

  if (args.command === "restore") {
    await restoreLastRun(repoRoot, metadataPath);
    return;
  }

  const yaml = loadYamlModule(repoRoot);
  const searchRoot = path.resolve(repoRoot, args.searchRoot);
  const specFiles = await findOpenApiFiles(searchRoot);

  if (specFiles.length === 0) {
    throw new Error(`No openapi.yaml files found under ${searchRoot}`);
  }

  const opportunities = [];
  for (const specFile of specFiles) {
    const raw = await fs.readFile(specFile, "utf8");
    const document = yaml.load(raw);
    if (!document || typeof document !== "object") {
      continue;
    }

    opportunities.push(...collectOpportunities(document, specFile));
  }

  const filtered = filterByMode(opportunities, args.mode);
  if (filtered.length === 0) {
    throw new Error(
      `No ${args.mode} mutation opportunities found under ${searchRoot}`,
    );
  }

  const selected = selectOpportunities(filtered, args);
  if (selected.length === 0) {
    throw new Error(
      `No opportunities selected for mode ${args.mode} and selection ${args.selection}`,
    );
  }

  if (args.dryRun) {
    process.stdout.write(
      JSON.stringify(
        {
          mode: args.mode,
          selection: args.selection,
          searchRoot,
          totalOpportunities: filtered.length,
          selectedCount: selected.length,
          selected,
        },
        null,
        2,
      ),
    );
    return;
  }

  const metadata = await applyOpportunities({
    repoRoot,
    metadataPath,
    selected,
    yaml,
    force: args.force,
  });

  process.stdout.write(JSON.stringify(metadata, null, 2));
}

function parseArgs(argv) {
  const args = {
    command: "apply",
    repoRoot: process.cwd(),
    searchRoot: ".",
    mode: "random",
    selection: "single",
    dryRun: false,
    force: false,
    index: null,
  };

  for (let i = 0; i < argv.length; i++) {
    const token = argv[i];
    switch (token) {
      case "apply":
      case "restore":
        args.command = token;
        break;
      case "--repo-root":
        args.repoRoot = argv[++i];
        break;
      case "--search-root":
        args.searchRoot = argv[++i];
        break;
      case "--mode":
        args.mode = argv[++i].toLowerCase();
        break;
      case "--selection":
        args.selection = argv[++i].toLowerCase();
        break;
      case "--dry-run":
        args.dryRun = true;
        break;
      case "--force":
        args.force = true;
        break;
      case "--index":
        args.index = Number.parseInt(argv[++i], 10);
        break;
      default:
        throw new Error(`Unknown argument: ${token}`);
    }
  }

  if (!["random", COMPATIBLE, INCOMPATIBLE].includes(args.mode)) {
    throw new Error(`Unsupported mode: ${args.mode}`);
  }

  if (!["single", "perspec"].includes(args.selection)) {
    throw new Error(`Unsupported selection: ${args.selection}`);
  }

  return args;
}

function loadYamlModule(repoRoot) {
  const candidates = [
    path.join(repoRoot, "web-frontend", "node_modules", "js-yaml"),
    path.join(repoRoot, "web-frontend", "node_modules", "yaml"),
  ];

  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch {
      // Try the next candidate.
    }
  }

  throw new Error(
    "Unable to locate a YAML parser. Expected js-yaml or yaml under web-frontend/node_modules.",
  );
}

async function findOpenApiFiles(rootDir) {
  const discovered = [];
  const queue = [rootDir];

  while (queue.length > 0) {
    const current = queue.shift();
    const entries = await fs.readdir(current, { withFileTypes: true });
    for (const entry of entries) {
      if (
        entry.name === ".specmatic" ||
        entry.name === "node_modules" ||
        entry.name === "build" ||
        entry.name.startsWith(".")
      ) {
        continue;
      }

      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        queue.push(fullPath);
      } else if (
        entry.isFile() &&
        entry.name.toLowerCase() === "openapi.yaml"
      ) {
        discovered.push(fullPath);
      }
    }
  }

  return discovered.sort();
}

function selectOpportunities(opportunities, args) {
  if (args.selection === "single") {
    const selected =
      args.index !== null
        ? opportunities[args.index]
        : opportunities[Math.floor(Math.random() * opportunities.length)];
    if (!selected) {
      throw new Error(
        `Requested opportunity index is out of range for mode ${args.mode}`,
      );
    }

    return [selected];
  }

  if (args.index !== null) {
    throw new Error("--index is only supported with --selection single");
  }

  const grouped = new Map();
  for (const opportunity of opportunities) {
    if (!grouped.has(opportunity.filePath)) {
      grouped.set(opportunity.filePath, []);
    }
    grouped.get(opportunity.filePath).push(opportunity);
  }

  const selected = [];
  for (const filePath of [...grouped.keys()].sort()) {
    const fileOpportunities = grouped.get(filePath);
    selected.push(
      fileOpportunities[Math.floor(Math.random() * fileOpportunities.length)],
    );
  }

  return selected;
}

function collectOpportunities(document, filePath) {
  const opportunities = [];
  const schemaEntries = Object.entries(document.components?.schemas ?? {});
  if (schemaEntries.length === 0) {
    return opportunities;
  }

  const compatibleTarget = findFirstCompatibleSchemaTarget(
    document,
    schemaEntries,
  );
  if (compatibleTarget) {
    opportunities.push({
      kind: "add-optional-schema-property",
      compatibility: COMPATIBLE,
      filePath,
      schemaName: compatibleTarget.schemaName,
      propertyName: compatibleTarget.propertyName,
      description: `Add optional property "${compatibleTarget.propertyName}" to schema "${compatibleTarget.schemaName}"`,
    });
  }

  const incompatibleTarget = findFirstIncompatibleSchemaTarget(
    document,
    schemaEntries,
  );
  if (incompatibleTarget) {
    opportunities.push({
      kind: "change-first-string-to-integer",
      compatibility: INCOMPATIBLE,
      filePath,
      schemaName: incompatibleTarget.schemaName,
      targetKind: incompatibleTarget.targetKind,
      propertyName: incompatibleTarget.propertyName ?? null,
      description: incompatibleTarget.propertyName
        ? `Change schema "${incompatibleTarget.schemaName}" property "${incompatibleTarget.propertyName}" from string to integer`
        : `Change schema "${incompatibleTarget.schemaName}" from string to integer`,
    });
  }

  return opportunities;
}

function filterByMode(opportunities, mode) {
  if (mode === "random") {
    return opportunities;
  }

  return opportunities.filter(
    (opportunity) => opportunity.compatibility === mode,
  );
}

async function applyOpportunities({
  repoRoot,
  metadataPath,
  selected,
  yaml,
  force,
}) {
  if (!force) {
    await assertNoPendingRun(metadataPath);
  }

  const metadataDir = path.dirname(metadataPath);
  await fs.mkdir(metadataDir, { recursive: true });

  const applied = [];
  for (const opportunity of selected) {
    const originalContent = await fs.readFile(opportunity.filePath, "utf8");
    const document = yaml.load(originalContent);
    const changeSummary = mutateDocument(document, opportunity);
    const nextContent = yaml.dump(document, {
      lineWidth: -1,
      noRefs: true,
      sortKeys: false,
    });

    const relativeFilePath = path.relative(repoRoot, opportunity.filePath);
    const backupPath = path.join(
      repoRoot,
      ".bcc-temp",
      "openapi-bcc",
      "originals",
      relativeFilePath,
    );

    await fs.mkdir(path.dirname(backupPath), { recursive: true });
    await fs.writeFile(backupPath, originalContent, "utf8");
    await fs.writeFile(opportunity.filePath, nextContent, "utf8");

    applied.push({
      filePath: opportunity.filePath,
      relativeFilePath,
      backupPath,
      selected: opportunity,
      changeSummary,
    });
  }

  const metadata = {
    timestamp: new Date().toISOString(),
    selectionCount: applied.length,
    applied,
  };

  await fs.writeFile(metadataPath, JSON.stringify(metadata, null, 2), "utf8");
  return metadata;
}

async function assertNoPendingRun(metadataPath) {
  try {
    await fs.access(metadataPath);
    throw new Error(
      `A previous randomized BCC change is still active. Restore it first or rerun with --force.`,
    );
  } catch (error) {
    if (error && error.code === "ENOENT") {
      return;
    }
    throw error;
  }
}

async function restoreLastRun(repoRoot, metadataPath) {
  let metadataRaw;
  try {
    metadataRaw = await fs.readFile(metadataPath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") {
      process.stdout.write(
        JSON.stringify(
          {
            restoredFiles: [],
            skipped: true,
            reason: "no-active-run",
          },
          null,
          2,
        ),
      );
      return;
    }
    throw error;
  }

  const metadata = JSON.parse(metadataRaw);
  const restoredFiles = [];

  for (const entry of metadata.applied ?? []) {
    const originalContent = await fs.readFile(entry.backupPath, "utf8");
    const targetPath = path.resolve(repoRoot, entry.relativeFilePath);
    await fs.writeFile(targetPath, originalContent, "utf8");
    restoredFiles.push(targetPath);
  }

  await fs.rm(path.join(repoRoot, ".bcc-temp", "openapi-bcc"), {
    recursive: true,
    force: true,
  });

  process.stdout.write(
    JSON.stringify(
      {
        restoredFiles,
      },
      null,
      2,
    ),
  );
}

function mutateDocument(document, selected) {
  switch (selected.kind) {
    case "add-optional-schema-property":
      return applyAddOptionalSchemaProperty(document, selected);
    case "change-first-string-to-integer":
      return applyChangeFirstStringToInteger(document, selected);
    default:
      throw new Error(`Unsupported opportunity kind: ${selected.kind}`);
  }
}

function applyAddOptionalSchemaProperty(document, selected) {
  const schema = resolveSchemaByName(document, selected.schemaName);
  if (!schema || schema.type !== "object") {
    throw new Error(`Unable to locate object schema "${selected.schemaName}"`);
  }

  if (!schema.properties || typeof schema.properties !== "object") {
    schema.properties = {};
  }

  schema.properties[selected.propertyName] = {
    type: "string",
    description: COMPATIBLE_PROPERTY_DESCRIPTION,
  };

  return {
    kind: selected.kind,
    target: selected.schemaName,
    propertyName: selected.propertyName,
  };
}

function applyChangeFirstStringToInteger(document, selected) {
  const schema = resolveSchemaByName(document, selected.schemaName);
  if (!schema) {
    throw new Error(`Unable to locate schema "${selected.schemaName}"`);
  }

  if (selected.targetKind === "schema") {
    schema.type = "integer";
    delete schema.format;
    return {
      kind: selected.kind,
      target: selected.schemaName,
    };
  }

  const propertySchema = resolveRef(
    document,
    schema.properties?.[selected.propertyName],
  );
  if (!propertySchema || propertySchema.type !== "string") {
    throw new Error(
      `Unable to locate string property "${selected.propertyName}" in schema "${selected.schemaName}"`,
    );
  }

  propertySchema.type = "integer";
  delete propertySchema.format;

  return {
    kind: selected.kind,
    target: selected.schemaName,
    propertyName: selected.propertyName,
  };
}

function resolveRef(document, value) {
  if (!value || typeof value !== "object" || !("$ref" in value)) {
    return value;
  }

  const ref = value.$ref;
  if (typeof ref !== "string" || !ref.startsWith("#/")) {
    return null;
  }

  const segments = ref.slice(2).split("/");
  let current = document;
  for (const segment of segments) {
    const key = segment.replace(/~1/g, "/").replace(/~0/g, "~");
    current = current?.[key];
    if (current === undefined) {
      return null;
    }
  }

  return current;
}

function buildUniqueName(existingNames, prefix) {
  let counter = 1;
  let candidate = `${prefix}${counter}`;
  while (existingNames.has(candidate)) {
    counter += 1;
    candidate = `${prefix}${counter}`;
  }

  return candidate;
}

function findFirstCompatibleSchemaTarget(document, schemaEntries) {
  for (const [schemaName, schemaEntry] of schemaEntries) {
    const schema = resolveRef(document, schemaEntry);
    if (!schema || schema.type !== "object") {
      continue;
    }

    const existingNames = new Set(Object.keys(schema.properties ?? {}));
    return {
      schemaName,
      propertyName: buildUniqueName(existingNames, COMPATIBLE_PROPERTY_NAME),
    };
  }

  return null;
}

function findFirstIncompatibleSchemaTarget(document, schemaEntries) {
  for (const [schemaName, schemaEntry] of schemaEntries) {
    const schema = resolveRef(document, schemaEntry);
    if (!schema || typeof schema !== "object") {
      continue;
    }

    if (schema.type === "string") {
      return {
        schemaName,
        targetKind: "schema",
      };
    }

    if (
      schema.type !== "object" ||
      !schema.properties ||
      typeof schema.properties !== "object"
    ) {
      continue;
    }

    for (const [propertyName, propertyEntry] of Object.entries(
      schema.properties,
    )) {
      const propertySchema = resolveRef(document, propertyEntry);
      if (propertySchema?.type === "string") {
        return {
          schemaName,
          targetKind: "property",
          propertyName,
        };
      }
    }
  }

  return null;
}

function resolveSchemaByName(document, schemaName) {
  return resolveRef(document, document.components?.schemas?.[schemaName]);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
