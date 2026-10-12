const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const url = require('url');

const PORT = 3000;

// 常用歌手/曲目繁簡對照表 (確保多語系皆能命中)
const SIMPLIFIED_MAP = {
  '周杰倫': '周杰伦',
  '蔡依林': '蔡依林',
  '林俊傑': '林俊杰',
  '陳奕迅': '陈奕迅',
  '五月天': '五月天',
  '孫燕姿': '孙燕姿',
  '王力宏': '王力宏',
  '張學友': '张学友',
  '劉德華': '刘德华',
  '鄧紫棋': '邓紫棋'
};

// 歌詞特殊符號或亂碼清理與正規化
function cleanLyricText(text) {
  if (!text) return '';
  return text
    .replace(/\uFFFD/g, '') // 移除 UTF-8 替換字元 (Replacement Character)
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '') // 移除不可見控制字元
    .replace(/\s+/g, ' ') // 連續空白摺疊
    .trim();
}

// 嚴格判斷歌詞內容是否包含有效的時間標籤格式
function hasValidSyncedLyrics(text) {
  if (!text || typeof text !== 'string') return false;
  // 必須包含形如 [00:12 或 [01:23.45] 的時間戳記
  return /\[\d{2}:\d{2}(?:\.\d{2,3})?\]/.test(text);
}

// 解析 LRC 格式 (支援同一行多個時間戳 [00:12.00][01:30.00]副歌、3 位數分鐘、[offset:±ms])
function parseLRC(lrcText) {
  const lines = lrcText.split(/\r?\n/);
  const result = [];
  const tagRegex = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;
  const offsetMatch = lrcText.match(/\[offset:\s*([+-]?\d+)\s*\]/i);
  // LRC 規範：正 offset 代表歌詞提早出現
  const offsetMs = offsetMatch ? parseInt(offsetMatch[1], 10) : 0;

  for (const rawLine of lines) {
    const line = rawLine.trim();
    const stamps = [];
    let m, lastIndex = 0;
    tagRegex.lastIndex = 0;
    // 只吃行首連續的時間標籤
    while ((m = tagRegex.exec(line)) && m.index === lastIndex) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      const frac = m[3] ? parseInt(m[3].padEnd(3, '0'), 10) : 0;
      stamps.push(min * 60000 + sec * 1000 + frac);
      lastIndex = tagRegex.lastIndex;
    }
    if (!stamps.length) continue;
    const text = cleanLyricText(line.slice(lastIndex));
    if (!text) continue;
    for (const ts of stamps) result.push({ timeMs: Math.max(0, ts - offsetMs), text });
  }

  return result.sort((a, b) => a.timeMs - b.timeMs);
}

// 通用 HTTPS GET 封裝 (明確以 UTF-8 解碼，避免字元編碼異常)
function requestJson(urlStr) {
  return new Promise((resolve, reject) => {
    https.get(urlStr, { headers: { 'User-Agent': 'IOS-Dynamic-Lyrics-Client/2.0' } }, (res) => {
      res.setEncoding('utf8');
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(JSON.parse(data));
          } else {
            resolve(null);
          }
        } catch (e) {
          resolve(null);
        }
      });
    }).on('error', () => resolve(null));
  });
}

// Spotify 歌名常帶有 " - Remastered 2011"、"(feat. X)"、"(with X)"、" - Radio Edit" 等後綴
// 注意：刻意「不」移除 Live / Acoustic / Remix，因為那些版本的時間軸與錄音室版不同
function stripTrackDecorations(track) {
  return track
    .replace(/\s*[-–]\s*(\d{4}\s+)?(Remaster(ed)?|Radio Edit|Single Version|Mono|Stereo)\b.*$/i, '')
    .replace(/\s*[(\[](feat\.?|ft\.?|with)\s[^)\]]*[)\]]/ig, '')
    .trim();
}

// Spotify Web API / 多歌手字串 "A, B" "A & B" "A feat. B" → 取主唱
function primaryArtist(artist) {
  return artist.split(/\s*(?:,|&|、|\sfeat\.?\s|\sft\.?\s|\sx\s)\s*/i)[0].trim();
}

// 從候選清單挑出：有時間軸 + 歌名相符 + 時長最接近 (已知時長時誤差須 <= tolerance 秒)
function pickBest(list, track, durationSec, tolerance = 5) {
  if (!Array.isArray(list)) return null;
  const t = track.toLowerCase();
  let candidates = list.filter(i => i.trackName && i.trackName.toLowerCase().includes(t) && hasValidSyncedLyrics(i.syncedLyrics));
  if (durationSec) {
    candidates = candidates
      .filter(i => typeof i.duration === 'number' && Math.abs(i.duration - durationSec) <= tolerance)
      .sort((a, b) => Math.abs(a.duration - durationSec) - Math.abs(b.duration - durationSec));
  }
  return candidates[0] || null;
}

// 多層級智慧抓取歌詞 (精確比對(含時長) -> 結構化搜尋 -> 繁簡轉換 -> 關鍵字搜尋 -> 單曲名(須時長吻合))
// 回傳 lrclib item；若曲目為純音樂回傳 { instrumental: true }
async function fetchLyricsWithFallback(track, artist, durationSec) {
  const rawTrack = track.trim();
  const cleanTrack = stripTrackDecorations(rawTrack) || rawTrack;
  const cleanArtist = primaryArtist(artist.trim());
  const dur = durationSec ? Math.round(Number(durationSec)) : null;

  const trackCandidates = [...new Set([rawTrack, cleanTrack])];
  const artistCandidates = [cleanArtist];
  if (SIMPLIFIED_MAP[cleanArtist]) artistCandidates.push(SIMPLIFIED_MAP[cleanArtist]);

  // 策略 1：/api/get 精確比對 (帶 duration 時 lrclib 會挑 ±2 秒內的版本，避免抓到 Live 版)
  for (const tr of trackCandidates) {
    for (const art of artistCandidates) {
      let url = `https://lrclib.net/api/get?track_name=${encodeURIComponent(tr)}&artist_name=${encodeURIComponent(art)}`;
      if (dur) url += `&duration=${dur}`;
      const data = await requestJson(url);
      if (data && data.instrumental) {
        console.log(`[Fetch] 純音樂: ${tr} - ${art}`);
        return { instrumental: true, trackName: data.trackName, artistName: data.artistName, duration: data.duration };
      }
      if (data && hasValidSyncedLyrics(data.syncedLyrics)) {
        console.log(`[Fetch] 策略 1 精確比對命中: ${tr} - ${art} (${data.duration}s)`);
        return data;
      }
    }
  }

  // 策略 2：結構化搜尋 /api/search?track_name=&artist_name= (比 q= 準確，不會混入 inst/翻唱)
  for (const art of artistCandidates) {
    const url = `https://lrclib.net/api/search?track_name=${encodeURIComponent(cleanTrack)}&artist_name=${encodeURIComponent(art)}`;
    const matched = pickBest(await requestJson(url), cleanTrack, dur);
    if (matched) {
      console.log(`[Fetch] 策略 2 結構化搜尋命中 (ID: ${matched.id}): ${matched.trackName} - ${matched.artistName}`);
      return matched;
    }
  }

  // 策略 3：關鍵字搜尋 /api/search?q=歌名 歌手
  for (const art of artistCandidates) {
    const url = `https://lrclib.net/api/search?q=${encodeURIComponent(`${cleanTrack} ${art}`)}`;
    const matched = pickBest(await requestJson(url), cleanTrack, dur);
    if (matched) {
      console.log(`[Fetch] 策略 3 關鍵字命中 (ID: ${matched.id}): ${matched.trackName} - ${matched.artistName}`);
      return matched;
    }
  }

  // 策略 4：僅以歌名搜尋 (處理歌手名中英不一致，如 薛之謙 ↔ Joker Xue)
  // 同名歌曲極多，必須有時長且誤差 <= 3 秒才接受，否則寧可回傳找不到
  if (dur) {
    const url = `https://lrclib.net/api/search?q=${encodeURIComponent(cleanTrack)}`;
    const list = await requestJson(url);
    const exact = Array.isArray(list) ? list.filter(i => i.trackName && i.trackName.toLowerCase() === cleanTrack.toLowerCase()) : null;
    const matched = pickBest(exact, cleanTrack, dur, 3);
    if (matched) {
      console.log(`[Fetch] 策略 4 單曲名+時長命中 (ID: ${matched.id}): ${matched.trackName} - ${matched.artistName}`);
      return matched;
    }
  }

  return null;
}

// 伺服器
const server = http.createServer(async (req, res) => {
  const parsedUrl = url.parse(req.url, true);

  // API: 取得即時歌詞
  if (parsedUrl.pathname === '/api/lyrics') {
    const track = (parsedUrl.query.track || '夜曲').toString();
    const artist = (parsedUrl.query.artist || '周杰倫').toString();
    const duration = parsedUrl.query.duration ? Number(parsedUrl.query.duration) : null;

    try {
      const data = await fetchLyricsWithFallback(track, artist, duration);
      if (data && data.instrumental) {
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({
          trackName: data.trackName || track,
          artistName: data.artistName || artist,
          duration: data.duration || duration || 230,
          instrumental: true,
          lyrics: [{ timeMs: 0, text: '♪ 純音樂 ♪' }],
          rawLrc: ''
        }));
      } else if (data && hasValidSyncedLyrics(data.syncedLyrics)) {
        const parsed = parseLRC(data.syncedLyrics);
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({
          trackName: data.trackName || track,
          artistName: data.artistName || artist,
          duration: data.duration || 230,
          lyrics: parsed,
          rawLrc: data.syncedLyrics
        }));
      } else {
        res.writeHead(404, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ error: `找不到【${track}】的時間軸歌詞，請確認歌名或稍後再試` }));
      }
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ error: err.message }));
    }
    return;
  }

  // 圖示靜態檔案
  if (parsedUrl.pathname === '/icon.jpg') {
    const iconPath = path.join(__dirname, 'icon.jpg');
    fs.readFile(iconPath, (err, content) => {
      if (err) {
        res.writeHead(404);
        res.end('Not Found');
      } else {
        res.writeHead(200, { 'Content-Type': 'image/jpeg' });
        res.end(content);
      }
    });
    return;
  }

  // 首頁靜態網頁
  if (parsedUrl.pathname === '/' || parsedUrl.pathname === '/index.html') {
    const filePath = path.join(__dirname, 'index.html');
    fs.readFile(filePath, 'utf8', (err, content) => {
      if (err) {
        res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('Error loading index.html');
      } else {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(content);
      }
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('Not Found');
});

if (require.main === module) {
  server.listen(PORT, () => {
    console.log(`[Simulator Server] Running on http://localhost:${PORT}`);
  });
}

module.exports = { fetchLyricsWithFallback, parseLRC, stripTrackDecorations, primaryArtist };
