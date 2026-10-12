const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const url = require('url');

const PORT = 3000;

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

function cleanLyricText(text) {
  if (!text) return '';
  return text
    .replace(/\uFFFD/g, '')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function hasValidSyncedLyrics(text) {
  if (!text || typeof text !== 'string') return false;
  return /\[\d{2}:\d{2}(?:\.\d{2,3})?\]/.test(text);
}

function parseLRC(lrcText) {
  const lines = lrcText.split(/\r?\n/);
  const result = [];
  const timeRegex = /\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\]/g;

  for (const rawLine of lines) {
    const trimmed = rawLine.trim();
    if (!trimmed) continue;
    const timestamps = [];
    let match;
    timeRegex.lastIndex = 0;
    while ((match = timeRegex.exec(trimmed)) !== null) {
      const min = parseInt(match[1], 10);
      const sec = parseInt(match[2], 10);
      let ms = 0;
      if (match[3]) {
        ms = match[3].length === 2 ? parseInt(match[3], 10) * 10 : parseInt(match[3], 10);
      }
      timestamps.push(min * 60 * 1000 + sec * 1000 + ms);
    }
    if (timestamps.length === 0) continue;

    const text = cleanLyricText(trimmed.replace(timeRegex, ''));
    if (!text) continue;
    for (const timeMs of timestamps) {
      result.push({ timeMs, text });
    }
  }

  return result.sort((a, b) => a.timeMs - b.timeMs);
}

function requestJson(urlStr) {
  return new Promise((resolve) => {
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

// 取得高解析度專輯封面
async function fetchArtwork(track, artist) {
  const query = `${track} ${artist}`;
  const url = `https://itunes.apple.com/search?term=${encodeURIComponent(query)}&entity=song&limit=1`;
  const data = await requestJson(url);
  if (data && Array.isArray(data.results) && data.results.length > 0 && data.results[0].artworkUrl100) {
    return data.results[0].artworkUrl100.replace('100x100bb', '300x300bb');
  }
  return null;
}

function stripTrackDecorations(track) {
  let t = track;
  t = t.replace(/\s*[-–]\s*(\d{4}\s+)?(Remaster(ed)?|Radio Edit|Single Version|Mono|Stereo)\b.*$/i, '');
  t = t.replace(/\s*[(\[](feat\.?|ft\.?|with)\s[^)\]]*[)\]]/i, '');
  return t.trim() || track;
}

function primaryArtist(artist) {
  const parts = artist.split(/[,&、]/);
  let first = parts[0] || artist;
  const featMatch = first.match(/\s(feat\.?|ft\.?|x)\s/i);
  if (featMatch) {
    first = first.slice(0, featMatch.index);
  }
  return first.trim();
}

function pickBest(list, cleanTrack, targetDurationSec) {
  if (!Array.isArray(list) || list.length === 0) return null;
  const lowerTrack = cleanTrack.toLowerCase();
  const eligible = list.filter(item => {
    if (!item.trackName) return false;
    const name = item.trackName.toLowerCase();
    const nameMatches = name === lowerTrack || name.includes(lowerTrack) || lowerTrack.includes(name);
    return nameMatches && (hasValidSyncedLyrics(item.syncedLyrics) || item.instrumental);
  });
  if (eligible.length === 0) return null;

  if (targetDurationSec) {
    eligible.sort((a, b) => {
      const diffA = a.duration ? Math.abs(a.duration - targetDurationSec) : 9999;
      const diffB = b.duration ? Math.abs(b.duration - targetDurationSec) : 9999;
      return diffA - diffB;
    });
    const best = eligible[0];
    if (!best.duration || Math.abs(best.duration - targetDurationSec) <= 15) {
      return best;
    }
  }
  return eligible[0];
}

async function fetchLyricsWithFallback(track, artist, durationSec) {
  const rawTrack = track.trim();
  const cleanTrack = stripTrackDecorations(rawTrack) || rawTrack;
  const cleanArtist = primaryArtist(artist.trim());
  const dur = durationSec ? Math.round(Number(durationSec)) : null;

  const trackCandidates = [...new Set([rawTrack, cleanTrack])];
  const artistCandidates = [cleanArtist];
  if (SIMPLIFIED_MAP[cleanArtist]) artistCandidates.push(SIMPLIFIED_MAP[cleanArtist]);

  for (const tr of trackCandidates) {
    for (const art of artistCandidates) {
      let url = `https://lrclib.net/api/get?track_name=${encodeURIComponent(tr)}&artist_name=${encodeURIComponent(art)}`;
      if (dur) url += `&duration=${dur}`;
      const data = await requestJson(url);
      if (data && data.instrumental) {
        return { instrumental: true, trackName: data.trackName, artistName: data.artistName, duration: data.duration };
      }
      if (data && hasValidSyncedLyrics(data.syncedLyrics)) {
        return data;
      }
    }
  }

  for (const art of artistCandidates) {
    const url = `https://lrclib.net/api/search?track_name=${encodeURIComponent(cleanTrack)}&artist_name=${encodeURIComponent(art)}`;
    const matched = pickBest(await requestJson(url), cleanTrack, dur);
    if (matched) return matched;
  }

  for (const art of artistCandidates) {
    const url = `https://lrclib.net/api/search?q=${encodeURIComponent(`${cleanTrack} ${art}`)}`;
    const matched = pickBest(await requestJson(url), cleanTrack, dur);
    if (matched) return matched;
  }

  const queryOnlyTrack = `https://lrclib.net/api/search?q=${encodeURIComponent(cleanTrack)}`;
  return pickBest(await requestJson(queryOnlyTrack), cleanTrack, dur);
}

const server = http.createServer(async (req, res) => {
  const parsedUrl = url.parse(req.url, true);

  if (parsedUrl.pathname === '/api/lyrics') {
    const track = (parsedUrl.query.track || '夜曲').toString();
    const artist = (parsedUrl.query.artist || '周杰倫').toString();
    const duration = parsedUrl.query.duration ? Number(parsedUrl.query.duration) : null;

    try {
      const [data, artworkUrl] = await Promise.all([
        fetchLyricsWithFallback(track, artist, duration),
        fetchArtwork(track, artist)
      ]);

      if (data && data.instrumental) {
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({
          trackName: data.trackName || track,
          artistName: data.artistName || artist,
          duration: data.duration || duration || 230,
          instrumental: true,
          artworkUrl: artworkUrl,
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
          artworkUrl: artworkUrl,
          lyrics: parsed,
          rawLrc: data.syncedLyrics
        }));
      } else {
        res.writeHead(404, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ error: `找不到【${track}】的時間軸歌詞` }));
      }
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ error: err.message }));
    }
    return;
  }

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

server.listen(PORT, () => {
  console.log(`[Simulator Server] Running on http://localhost:${PORT}`);
});
