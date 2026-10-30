// Read-only verification of the running app-owned CamillaDSP pipeline.
// Usage: node scripts/verify-native-elevation.mjs LABEL EXPECTED_DEGREES [SECONDS] [STRATEGY]
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { setTimeout as pause } from 'node:timers/promises';

const [label, angleText, durationText = '12', expectedStrategy] = process.argv.slice(2);
const expected = Number(angleText), duration = Number(durationText);
if (!label || !Number.isFinite(expected) || !Number.isFinite(duration) || duration < 1 || duration > 30) throw Error('Invalid verification arguments');
const project = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const evidence = path.join(project, 'Documentation/Center-Elevation-2026-10-29');
const support = path.join(os.homedir(), 'Library/Application Support/FieldWeave');
const receipt = JSON.parse(fs.readFileSync(path.join(support, 'LiveAudioRoute.json'), 'utf8'));
const command = execFileSync('/bin/ps', ['-p', String(receipt.processID), '-o', 'command='], { encoding: 'utf8' });
const port = command.match(/-p (\d+)/)?.[1];
if (!port || !command.includes('/usr/local/bin/camilladsp')) throw Error('The app-owned engine is unavailable');
const socket = new WebSocket(`ws://127.0.0.1:${port}`);
await new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(Error('Websocket startup timed out')), 3000);
  socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, { once: true });
  socket.addEventListener('error', () => { clearTimeout(timer); reject(Error('Websocket startup failed')); }, { once: true });
});
async function request(name) {
  return await new Promise((resolve, reject) => {
    const receive = event => {
      clearTimeout(timer);
      try {
        const response = JSON.parse(String(event.data))[name];
        if (response?.result !== 'Ok') throw Error(`Engine rejected ${name}`);
        resolve(response.value);
      } catch (error) { reject(error); }
    };
    const timer = setTimeout(() => { socket.removeEventListener('message', receive); reject(Error(`${name} timed out`)); }, 3000);
    socket.addEventListener('message', receive, { once: true });
    socket.send(JSON.stringify(name));
  });
}
function stereoRMS(values) {
  if (!Array.isArray(values) || values.length !== 2) return null;
  const power = values.reduce((sum, value) => sum + 10 ** (value / 10), 0) / 2;
  return power > 0 ? 10 * Math.log10(power) : null;
}
try {
  let active, report, config;
  for (let attempt = 0; attempt < 30; attempt++) {
    active = JSON.parse(await request('GetConfigJson'));
    const directory = path.dirname(active.filters.LL.parameters.filename);
    report = JSON.parse(fs.readFileSync(path.join(directory, 'report.json'), 'utf8'));
    config = JSON.parse(fs.readFileSync(path.join(directory, 'configuration.json'), 'utf8'));
    if (Math.abs(report.center_elevation_degrees - expected) < 0.001 && (!expectedStrategy || report.center_elevation_strategy === expectedStrategy)) break;
    if (attempt === 29) throw Error(`Expected ${expected} degrees/${expectedStrategy ?? 'any strategy'}, active ${report.center_elevation_degrees}/${report.center_elevation_strategy}`);
    await pause(200);
  }
  for (const name of ['FWBalanceCalibration', 'FWBalanceTrim', 'FWBalanceCeiling']) {
    if (!active.filters[name]) throw Error(`Missing always-on output stage: ${name}`);
  }
  await request('GetSignalLevelsSinceLast');
  const samples = [], started = performance.now();
  while ((performance.now() - started) / 1000 < duration) {
    await pause(500);
    const state = await request('GetState');
    if (state !== 'Running') throw Error(`Engine state ${state}`);
    const levels = await request('GetSignalLevelsSinceLast');
    const faders = await request('GetFaders');
    samples.push({ seconds: (performance.now() - started) / 1000,
      capture_rms_dbfs: stereoRMS(levels.capture_rms), playback_rms_dbfs: stereoRMS(levels.playback_rms),
      capture_peak_dbfs: Math.max(...levels.capture_peak), playback_peak_dbfs: Math.max(...levels.playback_peak),
      trim_db: faders[1].volume });
  }
  const clipped = await request('GetClippedSamples');
  const finalActive = JSON.parse(await request('GetConfigJson'));
  if (finalActive.filters.LL.parameters.filename !== active.filters.LL.parameters.filename) throw Error('Pipeline changed during measurement');
  const target = config.safety.preamp_db - 6;
  const tail = samples.filter(sample => sample.seconds >= Math.max(0, duration - 2) && sample.capture_rms_dbfs > -70 && sample.playback_rms_dbfs > -90);
  const error = tail.length ? tail.reduce((sum, sample) => sum + sample.playback_rms_dbfs - sample.capture_rms_dbfs - target, 0) / tail.length : null;
  const activeDirectory = path.dirname(active.filters.LL.parameters.filename);
  const result = { label, verified: clipped === 0, degrees: expected,
    profile: report.center_elevation_profile ?? null, strategy: report.center_elevation_strategy,
    target_gain_db: target, final_mean_error_db: error, clipped_samples: clipped,
    engine_pid: receipt.processID, capture_uid: receipt.captureUID, playback_uid: receipt.playbackUID,
    final_fir_taps: report.matrix_taps, active_fir_directory: activeDirectory,
    height_attribution_exported: fs.existsSync(path.join(activeDirectory, 'CENTER-HEIGHT-ATTRIBUTION.txt')),
    height_provenance_exported: fs.existsSync(path.join(activeDirectory, 'center-height-provenance.json')), samples };
  fs.mkdirSync(evidence, { recursive: true });
  const savedFIR = path.join(evidence, 'Native-FIR', label);
  fs.mkdirSync(savedFIR, { recursive: true });
  for (const name of ['LL.wav','LR.wav','RL.wav','RR.wav','configuration.json','report.json','live-loudness.json','CENTER-HEIGHT-ATTRIBUTION.txt','center-height-provenance.json','camilladsp-offline.yml']) {
    const source = path.join(activeDirectory, name);
    if (fs.existsSync(source)) fs.copyFileSync(source, path.join(savedFIR, name));
  }
  if (fs.existsSync(path.join(activeDirectory, 'assets'))) fs.cpSync(path.join(activeDirectory, 'assets'), path.join(savedFIR, 'assets'), { recursive: true });
  result.saved_fir_directory = savedFIR;
  fs.writeFileSync(path.join(evidence, `Native-${label}.json`), JSON.stringify(result, null, 2) + '\n');
  if (clipped !== 0) throw Error('Device clipping detected');
  console.log(JSON.stringify({ label, degrees: expected, profile: result.profile, strategy: result.strategy, final_mean_error_db: error, clipped_samples: clipped, samples: samples.length }));
} finally { socket.close(); }
