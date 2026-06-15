#!/usr/bin/env node
const fs = require('fs');

const API_KEY = 'fk-v729N6lFPnSJ6UnPqaXZYWUu4KCpNqyheKZS9Ro22UK8bnG6';
const API_BASE = 'https://openapi.felo.ai';
const query = fs.readFileSync('C:\\Users\\HAKIMIE\\smartponic_v2\\felo_query.txt', 'utf8').trim();

async function main() {
  console.error(`Creating PPT task (query: ${query.length} chars)...`);

  // Step 1: Create task
  const createRes = await fetch(`${API_BASE}/v2/ppts`, {
    method: 'POST',
    headers: {
      'Accept': 'application/json',
      'Authorization': `Bearer ${API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query })
  });

  if (!createRes.ok) {
    const err = await createRes.text();
    throw new Error(`Create failed: HTTP ${createRes.status} ${err.slice(0,200)}`);
  }

  const createData = (await createRes.json()).data || {};
  const taskId = createData.task_id;
  if (!taskId) throw new Error('No task_id in response');

  console.error(`Task ID: ${taskId}`);
  console.error('Polling every 15s (max 30 min)...\n');

  // Step 2: Poll until done
  const startAt = Date.now();
  const maxWait = 1800000;
  const interval = 15000;

  while (Date.now() - startAt <= maxWait) {
    await new Promise(r => setTimeout(r, interval));

    const histRes = await fetch(`${API_BASE}/v2/tasks/${taskId}/historical`, {
      headers: {
        'Accept': 'application/json',
        'Authorization': `Bearer ${API_KEY}`,
      }
    });

    if (!histRes.ok) {
      console.error(`Poll HTTP ${histRes.status}, retrying...`);
      continue;
    }

    const histData = (await histRes.json()).data || {};
    const status = String(histData.task_status || histData.status || '').trim().toUpperCase();
    const elapsed = Math.floor((Date.now() - startAt) / 1000);

    console.error(`[${elapsed}s] Status: ${status}`);

    if (status === 'COMPLETED' || status === 'SUCCESS') {
      const pptUrl = histData.ppt_url || '';
      const liveDocUrl = histData.live_doc_url ||
        (histData.live_doc_short_id || histData.livedoc_short_id || createData.livedoc_short_id
          ? `https://felo.ai/livedoc/${histData.live_doc_short_id || histData.livedoc_short_id || createData.livedoc_short_id}`
          : '');
      const displayUrl = pptUrl || liveDocUrl;

      if (!displayUrl) throw new Error('No URL in completed task');

      console.log('\n' + JSON.stringify({
        status: 'ok',
        data: {
          task_id: taskId,
          ppt_url: pptUrl || null,
          live_doc_url: liveDocUrl || null,
          livedoc_short_id: createData.livedoc_short_id || histData.live_doc_short_id || null,
        }
      }, null, 2));
      return;
    }

    if (status === 'FAILED' || status === 'ERROR') {
      throw new Error(`Task failed with status: ${status}. Message: ${histData.message || ''}`);
    }
  }

  throw new Error(`Timed out. Task ID: ${taskId} — resume with --task-id ${taskId}`);
}

main().catch(err => {
  console.error(`\nERROR: ${err.message || err}`);
  process.exit(1);
});