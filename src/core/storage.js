import fs from 'node:fs/promises';
import path from 'node:path';

export function getDataPaths(baseDir) {
  const root = path.resolve(baseDir);
  return {
    root,
    identityFile: path.join(root, 'identity.json'),
    contactsFile: path.join(root, 'contacts.json'),
    stateFile: path.join(root, 'state.json'),
    inboxLogFile: path.join(root, 'inbox.log')
  };
}

export async function ensureDir(dirPath) {
  await fs.mkdir(dirPath, { recursive: true });
}

export async function readJson(filePath, fallbackValue) {
  try {
    const raw = await fs.readFile(filePath, 'utf8');
    return JSON.parse(raw);
  } catch (error) {
    if (error.code === 'ENOENT') {
      return fallbackValue;
    }
    throw error;
  }
}

export async function writeJson(filePath, value) {
  await ensureDir(path.dirname(filePath));
  const tmpPath = `${filePath}.tmp`;
  const serialized = `${JSON.stringify(value, null, 2)}\n`;
  await fs.writeFile(tmpPath, serialized, 'utf8');
  await fs.rename(tmpPath, filePath);
}

export async function appendLine(filePath, line) {
  await ensureDir(path.dirname(filePath));
  await fs.appendFile(filePath, `${line}\n`, 'utf8');
}
