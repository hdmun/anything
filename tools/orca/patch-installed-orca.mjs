import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execSync } from 'node:child_process';

// 1. Target detection
function findOrcaAsarPath() {
  const localAppData = process.env.LOCALAPPDATA || path.join(process.env.USERPROFILE || '', 'AppData', 'Local');
  const candidates = [
    path.join(localAppData, 'Programs', 'orca', 'resources', 'app.asar'),
    path.join(localAppData, 'Programs', 'Orca', 'resources', 'app.asar'),
    'C:\\Program Files\\orca\\resources\\app.asar',
    'C:\\Program Files\\Orca\\resources\\app.asar'
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return null;
}

// 2. Terminate Orca processes if running
function killOrcaProcesses() {
  try {
    if (process.platform === 'win32') {
      execSync('taskkill /F /IM Orca.exe /T 2>nul', { stdio: 'ignore' });
    }
  } catch {}
}

const polyfillScript = `<script>
(function() {
  var g = typeof globalThis !== 'undefined' ? globalThis : window;
  if (!g.crypto) g.crypto = {};
  if (typeof g.crypto.randomUUID !== 'function') {
    g.crypto.randomUUID = function() {
      return '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, function(c) {
        var r = g.crypto.getRandomValues
          ? g.crypto.getRandomValues(new Uint8Array(1))[0]
          : Math.floor(Math.random() * 256);
        return (c ^ (r & (15 >> (c / 4)))).toString(16);
      });
    };
  }
})();
</script>`;

function calculateIntegrity(buffer) {
  const blockSize = 4194304;
  const hash = crypto.createHash('sha256').update(buffer).digest('hex');
  return {
    algorithm: 'SHA256',
    hash,
    blockSize,
    blocks: [hash]
  };
}

function createHeaderBuffer(headerJson) {
  const jsonBuf = Buffer.from(headerJson, 'utf8');
  const jsonLen = jsonBuf.length;
  const padding = (4 - (jsonLen % 4)) % 4;
  const picklePayloadSize = 4 + jsonLen + padding;

  const buf = Buffer.alloc(16 + jsonLen + padding);
  buf.writeUInt32LE(4, 0);
  buf.writeUInt32LE(picklePayloadSize + 4, 4);
  buf.writeUInt32LE(picklePayloadSize, 8);
  buf.writeUInt32LE(jsonLen, 12);
  jsonBuf.copy(buf, 16);
  return buf;
}

function collectPackedFiles(node, currentPath = '') {
  let files = [];
  if (node.files) {
    for (const [name, child] of Object.entries(node.files)) {
      const fullPath = currentPath ? `${currentPath}/${name}` : name;
      if (child.files) {
        files = files.concat(collectPackedFiles(child, fullPath));
      } else if (!child.unpacked && typeof child.offset === 'string') {
        files.push({
          path: fullPath,
          node: child,
          oldOffset: parseInt(child.offset, 10),
          oldSize: child.size
        });
      }
    }
  }
  return files;
}

function countUnpackedEntries(node) {
  let count = 0;
  if (node.files) {
    for (const child of Object.values(node.files)) {
      if (child.unpacked) count++;
      if (child.files) count += countUnpackedEntries(child);
    }
  }
  return count;
}

async function run() {
  console.log(`=== Orca Web Client Insecure Context Polyfill Patcher ===\n`);
  const asarPath = findOrcaAsarPath();
  if (!asarPath) {
    console.error('[!] Orca app.asar not found! Please verify Orca is installed.');
    process.exit(1);
  }
  console.log(`[*] Found Orca asar at:\n    ${asarPath}`);

  console.log('[*] Stopping Orca processes if running...');
  killOrcaProcesses();

  const backupPath = asarPath + '.bak';
  const patchedPath = asarPath + '.patched';

  console.log('[*] Backing up app.asar -> app.asar.bak...');
  fs.copyFileSync(asarPath, backupPath);

  const fd = fs.openSync(asarPath, 'r');
  const metaBuf = Buffer.alloc(16);
  fs.readSync(fd, metaBuf, 0, 16, 0);
  const jsonLen = metaBuf.readUInt32LE(12);
  const headerSize = metaBuf.readUInt32LE(4);
  const payloadStart = 8 + headerSize;

  const jsonBuf = Buffer.alloc(jsonLen);
  fs.readSync(fd, jsonBuf, 0, jsonLen, 16);
  const header = JSON.parse(jsonBuf.toString('utf8'));

  const originalUnpackedCount = countUnpackedEntries(header);
  const packedFiles = collectPackedFiles(header);
  packedFiles.sort((a, b) => a.oldOffset - b.oldOffset);
  console.log(`[*] Discovered ${packedFiles.length} packed files (${originalUnpackedCount} unpacked metadata records).`);

  const replacements = new Map();
  let alreadyPatched = false;

  for (const targetPath of ['out/web/web-index.html', 'out/renderer/web-index.html']) {
    const item = packedFiles.find(f => f.path === targetPath);
    if (item) {
      const originalBuf = Buffer.alloc(item.oldSize);
      fs.readSync(fd, originalBuf, 0, item.oldSize, payloadStart + item.oldOffset);
      const originalHtml = originalBuf.toString('utf8');

      if (originalHtml.includes('g.crypto.randomUUID')) {
        console.log(`[*] ${targetPath} is ALREADY patched.`);
        alreadyPatched = true;
        continue;
      }

      let patchedHtml;
      if (originalHtml.includes('<meta charset="UTF-8" />')) {
        patchedHtml = originalHtml.replace('<meta charset="UTF-8" />', `<meta charset="UTF-8" />\n    ${polyfillScript}`);
      } else {
        patchedHtml = originalHtml.replace('<head>', `<head>\n    ${polyfillScript}`);
      }

      const newBuf = Buffer.from(patchedHtml, 'utf8');
      replacements.set(targetPath, newBuf);
      console.log(`[*] Injected polyfill into ${targetPath} (+${newBuf.length - item.oldSize} bytes)`);
    }
  }

  if (replacements.size === 0) {
    fs.closeSync(fd);
    if (alreadyPatched) {
      console.log('\n[+] app.asar is already up to date with the polyfill. No changes needed!');
      return;
    }
    console.error('[!] Could not locate web-index.html in asar!');
    process.exit(1);
  }

  // Recalculate offsets
  let currentOffset = 0;
  for (const item of packedFiles) {
    const newBuf = replacements.get(item.path);
    const size = newBuf ? newBuf.length : item.oldSize;
    item.node.offset = currentOffset.toString();
    item.node.size = size;
    if (newBuf) {
      item.node.integrity = calculateIntegrity(newBuf);
    }
    currentOffset += size;
  }

  console.log('[*] Writing patched asar...');
  const newHeaderBuf = createHeaderBuffer(JSON.stringify(header));
  const outFd = fs.openSync(patchedPath, 'w');
  fs.writeSync(outFd, newHeaderBuf);

  const CHUNK_SIZE = 1024 * 1024;
  const copyBuf = Buffer.alloc(CHUNK_SIZE);

  for (const item of packedFiles) {
    const newBuf = replacements.get(item.path);
    if (newBuf) {
      fs.writeSync(outFd, newBuf);
    } else {
      let remaining = item.oldSize;
      let readPos = payloadStart + item.oldOffset;
      while (remaining > 0) {
        const toRead = Math.min(remaining, CHUNK_SIZE);
        fs.readSync(fd, copyBuf, 0, toRead, readPos);
        fs.writeSync(outFd, copyBuf, 0, toRead);
        remaining -= toRead;
        readPos += toRead;
      }
    }
  }

  fs.closeSync(fd);
  fs.closeSync(outFd);

  // Self-verification without external dependencies
  console.log('[*] Verifying patched asar integrity...');
  const verifyFd = fs.openSync(patchedPath, 'r');
  const verifyMeta = Buffer.alloc(16);
  fs.readSync(verifyFd, verifyMeta, 0, 16, 0);
  const verifyJsonLen = verifyMeta.readUInt32LE(12);
  const verifyHeaderSize = verifyMeta.readUInt32LE(4);
  const verifyPayloadStart = 8 + verifyHeaderSize;

  const verifyJsonBuf = Buffer.alloc(verifyJsonLen);
  fs.readSync(verifyFd, verifyJsonBuf, 0, verifyJsonLen, 16);
  const verifyHeader = JSON.parse(verifyJsonBuf.toString('utf8'));

  const verifyUnpackedCount = countUnpackedEntries(verifyHeader);
  if (verifyUnpackedCount !== originalUnpackedCount) {
    fs.closeSync(verifyFd);
    fs.unlinkSync(patchedPath);
    throw new Error(`Unpacked metadata count mismatch: got ${verifyUnpackedCount}, expected ${originalUnpackedCount}`);
  }

  const verifyWebIndex = verifyHeader.files?.out?.files?.web?.files?.['web-index.html'];
  if (!verifyWebIndex) {
    fs.closeSync(verifyFd);
    fs.unlinkSync(patchedPath);
    throw new Error('Verification failed: out/web/web-index.html missing in patched header!');
  }

  const verifyHtmlBuf = Buffer.alloc(verifyWebIndex.size);
  fs.readSync(verifyFd, verifyHtmlBuf, 0, verifyWebIndex.size, verifyPayloadStart + parseInt(verifyWebIndex.offset, 10));
  fs.closeSync(verifyFd);

  if (!verifyHtmlBuf.toString('utf8').includes('g.crypto.randomUUID')) {
    fs.unlinkSync(patchedPath);
    throw new Error('Verification failed: polyfill not detected in verified payload!');
  }

  // Atomically replace app.asar
  fs.copyFileSync(patchedPath, asarPath);
  fs.unlinkSync(patchedPath);

  console.log('\n[✔] SUCCESS: Orca app.asar has been successfully patched!');
  console.log('[*] You can now launch Orca and connect from your browser.');
}

run().catch(err => {
  console.error('\n[X] Error patching Orca:', err.message);
  process.exit(1);
});
