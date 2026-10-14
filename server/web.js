'use strict';

const http = require('node:http');
const crypto = require('node:crypto');
const { URL, URLSearchParams } = require('node:url');

const RESOURCE = GetCurrentResourceName();
const enabled = GetConvar('seam_admin_web_enabled', 'false') === 'true';
const port = Math.max(1, Number(GetConvar('seam_admin_web_port', '30121')) || 30121);
const host = GetConvar('seam_admin_web_host', '127.0.0.1');
const publicUrl = GetConvar('seam_admin_public_url', '').replace(/\/$/, '');
const discordClientId = GetConvar('seam_admin_discord_client_id', '');
const discordSecret = GetConvar('seam_admin_discord_client_secret', '');
const cookieSecure = publicUrl.startsWith('https://');

const sessions = new Map();
const oauthStates = new Map();
const pending = new Map();
const streams = new Map();
const rateLimits = new Map();
let requestCounter = 0;
let server;

const mimeTypes = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.woff2': 'font/woff2',
    '.json': 'application/json; charset=utf-8',
};

function randomToken(bytes = 32) {
    return crypto.randomBytes(bytes).toString('base64url');
}

function parseCookies(req) {
    const output = {};
    for (const item of String(req.headers.cookie || '').split(';')) {
        const index = item.indexOf('=');
        if (index > 0) output[item.slice(0, index).trim()] = decodeURIComponent(item.slice(index + 1).trim());
    }
    return output;
}

function cookie(name, value, options = {}) {
    let text = `${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; SameSite=Lax`;
    if (cookieSecure) text += '; Secure';
    if (options.maxAge !== undefined) text += `; Max-Age=${options.maxAge}`;
    return text;
}

function sendJson(res, status, payload, headers = {}) {
    const body = JSON.stringify(payload);
    res.writeHead(status, {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Length': Buffer.byteLength(body),
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
        ...headers,
    });
    res.end(body);
}

function sendText(res, status, body, type = 'text/plain; charset=utf-8', headers = {}) {
    res.writeHead(status, {
        'Content-Type': type,
        'Content-Length': Buffer.byteLength(body),
        'X-Content-Type-Options': 'nosniff',
        ...headers,
    });
    res.end(body);
}

function getSession(req) {
    const id = parseCookies(req).seam_admin_session;
    const session = id && sessions.get(id);
    if (!session) return null;
    if (session.expiresAt < Date.now()) {
        sessions.delete(id);
        return null;
    }
    session.expiresAt = Date.now() + 12 * 60 * 60 * 1000;
    return session;
}

function readBody(req, limit = 65536) {
    return new Promise((resolve, reject) => {
        const chunks = [];
        let length = 0;
        req.on('data', chunk => {
            length += chunk.length;
            if (length > limit) {
                reject(new Error('Request body is too large.'));
                req.destroy();
            } else chunks.push(chunk);
        });
        req.on('end', () => {
            try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}); }
            catch { reject(new Error('Invalid JSON body.')); }
        });
        req.on('error', reject);
    });
}

function requestLua(user, action, payload) {
    return new Promise(resolve => {
        const id = `web:${++requestCounter}:${Date.now()}`;
        const timeout = setTimeout(() => {
            pending.delete(id);
            resolve({ ok: false, error: 'The FiveM server did not respond in time.' });
        }, 15000);
        pending.set(id, result => {
            clearTimeout(timeout);
            resolve(result);
        });
        emit('seam_admin:server:webRequest', id, user, action, payload || {});
    });
}

on('seam_admin:web:response', (requestId, result) => {
    const callback = pending.get(requestId);
    if (!callback) return;
    pending.delete(requestId);
    callback(result);
});

on('seam_admin:web:broadcast', payload => {
    const data = `event: update\ndata: ${JSON.stringify(payload || {})}\n\n`;
    for (const [id, stream] of streams) {
        if (stream.session.expiresAt < Date.now()) {
            try { stream.res.end(); } catch {}
            streams.delete(id);
        } else {
            try { stream.res.write(data); } catch { streams.delete(id); }
        }
    }
});

function checkRateLimit(session) {
    const now = Date.now();
    let entry = rateLimits.get(session.id);
    if (!entry || entry.resetAt < now) entry = { count: 0, resetAt: now + 60000 };
    entry.count++;
    rateLimits.set(session.id, entry);
    return entry.count <= 120;
}

function validOrigin(req) {
    if (!publicUrl) return false;
    const expected = new URL(publicUrl).origin;
    const origin = req.headers.origin;
    return !origin || origin === expected;
}

function serveAsset(pathname, res) {
    let asset = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
    if (asset.includes('..') || !/^[a-zA-Z0-9_./-]+$/.test(asset)) return sendText(res, 404, 'Not found');
    const content = LoadResourceFile(RESOURCE, `web/dist/${asset}`);
    if (content == null) {
        if (!asset.includes('.')) return serveAsset('/', res);
        return sendText(res, 404, 'Not found');
    }
    const extension = asset.includes('.') ? asset.slice(asset.lastIndexOf('.')).toLowerCase() : '.html';
    const body = Buffer.from(content);
    res.writeHead(200, {
        'Content-Type': mimeTypes[extension] || 'application/octet-stream',
        'Content-Length': body.length,
        'Cache-Control': asset === 'index.html' ? 'no-cache' : 'public, max-age=31536000, immutable',
        'Content-Security-Policy': "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://cdn.discordapp.com; connect-src 'self'; font-src 'self' data:; script-src 'self'; frame-ancestors 'none'",
        'Referrer-Policy': 'same-origin',
        'X-Frame-Options': 'DENY',
    });
    res.end(body);
}

async function exchangeDiscordCode(code) {
    const tokenResponse = await fetch('https://discord.com/api/v10/oauth2/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            client_id: discordClientId,
            client_secret: discordSecret,
            grant_type: 'authorization_code',
            code,
            redirect_uri: `${publicUrl}/auth/callback`,
        }),
    });
    if (!tokenResponse.ok) throw new Error(`Discord token exchange failed (${tokenResponse.status}).`);
    const token = await tokenResponse.json();
    const userResponse = await fetch('https://discord.com/api/v10/users/@me', {
        headers: { Authorization: `Bearer ${token.access_token}` },
    });
    if (!userResponse.ok) throw new Error(`Discord user lookup failed (${userResponse.status}).`);
    return userResponse.json();
}

async function handler(req, res) {
    const url = new URL(req.url, publicUrl || `http://${req.headers.host || 'localhost'}`);

    if (url.pathname === '/health') return sendJson(res, 200, { ok: true, resource: RESOURCE });

    if (url.pathname === '/login') {
        if (!publicUrl || !discordClientId || !discordSecret) {
            return sendText(res, 503, 'The web dashboard is not configured. See SeaM_Admin/README.md.');
        }
        const state = randomToken(24);
        oauthStates.set(state, Date.now() + 10 * 60 * 1000);
        const params = new URLSearchParams({
            client_id: discordClientId,
            redirect_uri: `${publicUrl}/auth/callback`,
            response_type: 'code',
            scope: 'identify',
            state,
            prompt: 'none',
        });
        res.writeHead(302, {
            Location: `https://discord.com/oauth2/authorize?${params}`,
            'Set-Cookie': cookie('seam_admin_oauth', state, { maxAge: 600 }),
            'Cache-Control': 'no-store',
        });
        return res.end();
    }

    if (url.pathname === '/auth/callback') {
        const cookies = parseCookies(req);
        const state = url.searchParams.get('state');
        const code = url.searchParams.get('code');
        const expiry = state && oauthStates.get(state);
        oauthStates.delete(state);
        if (!state || cookies.seam_admin_oauth !== state || !expiry || expiry < Date.now() || !code) {
            return sendText(res, 400, 'Invalid or expired Discord login. Return to the dashboard and try again.');
        }
        try {
            const discordUser = await exchangeDiscordCode(code);
            const user = {
                id: String(discordUser.id),
                username: discordUser.global_name || discordUser.username,
                avatar: discordUser.avatar ? `https://cdn.discordapp.com/avatars/${discordUser.id}/${discordUser.avatar}.png?size=128` : null,
            };
            const authorised = await requestLua(user, 'bootstrap', {});
            if (!authorised.ok) return sendText(res, 403, authorised.error || 'This Discord account is not authorised.');
            const id = randomToken();
            sessions.set(id, { id, user, csrf: randomToken(24), expiresAt: Date.now() + 12 * 60 * 60 * 1000 });
            res.writeHead(302, {
                Location: '/',
                'Set-Cookie': [cookie('seam_admin_session', id, { maxAge: 43200 }), cookie('seam_admin_oauth', '', { maxAge: 0 })],
                'Cache-Control': 'no-store',
            });
            return res.end();
        } catch (error) {
            console.error(`[SeaM Admin] Discord OAuth failed: ${error.stack || error}`);
            return sendText(res, 502, 'Discord login failed. Check the server console and OAuth configuration.');
        }
    }

    if (url.pathname === '/api/bootstrap') {
        const session = getSession(req);
        if (!session) return sendJson(res, 401, { ok: false, loginUrl: '/login', error: 'Sign in with Discord to continue.' });
        const result = await requestLua(session.user, 'bootstrap', {});
        if (!result.ok) {
            sessions.delete(session.id);
            return sendJson(res, 403, result);
        }
        result.csrf = session.csrf;
        result.webUser = session.user;
        return sendJson(res, 200, result);
    }

    if (url.pathname === '/api/rpc' && req.method === 'POST') {
        const session = getSession(req);
        if (!session) return sendJson(res, 401, { ok: false, error: 'Your session expired. Sign in again.' });
        if (!validOrigin(req) || req.headers['x-csrf-token'] !== session.csrf) return sendJson(res, 403, { ok: false, error: 'Invalid request token.' });
        if (!checkRateLimit(session)) return sendJson(res, 429, { ok: false, error: 'Too many actions. Wait a moment and try again.' });
        try {
            const body = await readBody(req);
            const action = typeof body.action === 'string' ? body.action.slice(0, 80) : '';
            if (!action) return sendJson(res, 400, { ok: false, error: 'Missing action.' });
            const result = await requestLua(session.user, action, body.payload && typeof body.payload === 'object' ? body.payload : {});
            return sendJson(res, result.ok ? 200 : 400, result);
        } catch (error) {
            return sendJson(res, 400, { ok: false, error: error.message });
        }
    }

    if (url.pathname === '/api/stream') {
        const session = getSession(req);
        if (!session) return sendJson(res, 401, { ok: false });
        const id = randomToken(12);
        res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache, no-transform',
            Connection: 'keep-alive',
            'X-Accel-Buffering': 'no',
        });
        res.write('event: ready\ndata: {}\n\n');
        streams.set(id, { res, session });
        const keepalive = setInterval(() => { try { res.write(': keepalive\n\n'); } catch {} }, 25000);
        req.on('close', () => { clearInterval(keepalive); streams.delete(id); });
        return;
    }

    if (url.pathname === '/api/logout' && req.method === 'POST') {
        const session = getSession(req);
        if (session) sessions.delete(session.id);
        return sendJson(res, 200, { ok: true }, { 'Set-Cookie': cookie('seam_admin_session', '', { maxAge: 0 }) });
    }

    if (url.pathname.startsWith('/api/')) return sendJson(res, 404, { ok: false, error: 'API route not found.' });
    return serveAsset(url.pathname, res);
}

if (enabled) {
    server = http.createServer((req, res) => {
        Promise.resolve(handler(req, res)).catch(error => {
            console.error(`[SeaM Admin] Web request failed: ${error.stack || error}`);
            if (!res.headersSent) sendJson(res, 500, { ok: false, error: 'Internal server error.' });
            else res.end();
        });
    });
    server.listen(port, host, () => {
        console.log(`[SeaM Admin] Web dashboard listening on ${host}:${port}`);
        if (!publicUrl || !discordClientId || !discordSecret) console.log('[SeaM Admin] Add the web dashboard convars from README.md to finish Discord login setup.');
    });
    server.on('error', error => console.error(`[SeaM Admin] Web server error: ${error.message}`));
}

setInterval(() => {
    const now = Date.now();
    for (const [id, session] of sessions) if (session.expiresAt < now) sessions.delete(id);
    for (const [state, expiry] of oauthStates) if (expiry < now) oauthStates.delete(state);
    for (const [id, entry] of rateLimits) if (entry.resetAt + 60000 < now) rateLimits.delete(id);
}, 60000);

on('onResourceStop', resource => {
    if (resource === RESOURCE && server) server.close();
});
