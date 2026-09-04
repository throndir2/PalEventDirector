import { createRequire } from 'node:module';
import { openSync, writeSync, fsyncSync, closeSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';

// Reuse the CLI's pinned VM. This shim is test-only and is never packaged in PED.
const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = createRequire(require.resolve('fengari-node-cli/package.json'))('fengari');
const destination = path.resolve(process.argv[2]);
if (path.basename(destination) !== 'breadcrumbs.ndjson' ||
    path.dirname(path.dirname(destination)) !== path.resolve(tmpdir()) ||
    !path.basename(path.dirname(destination)).startsWith('ped-preflight-failfast-')) {
  throw new Error('fail-fast fixture must be confined to its temporary test directory');
}
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
let flushes = 0;
const openFiles = new Set();
lua.lua_getglobal(L, to_luastring('io'));
lua.lua_pushcfunction(L, (state) => {
  const filename = path.resolve(to_jsstring(lauxlib.luaL_checkstring(state, 1)));
  const mode = to_jsstring(lauxlib.luaL_checkstring(state, 2));
  if (filename !== destination || mode !== 'ab') return lauxlib.luaL_error(state, to_luastring('out-of-scope fixture file'));
  const fd = openSync(destination, 'a');
  openFiles.add(fd);
  lua.lua_newtable(state);
  const method = (name, callback) => {
    lua.lua_pushcfunction(state, callback);
    lua.lua_setfield(state, -2, to_luastring(name));
  };
  method('write', (child) => {
    const bytes = Buffer.from(lauxlib.luaL_checkstring(child, 2));
    if (writeSync(fd, bytes) !== bytes.length) return lauxlib.luaL_error(child, to_luastring('short fixture write'));
    lua.lua_pushvalue(child, 1);
    return 1;
  });
  method('flush', (child) => { fsyncSync(fd); flushes += 1; lua.lua_pushboolean(child, true); return 1; });
  method('close', (child) => { closeSync(fd); openFiles.delete(fd); lua.lua_pushboolean(child, true); return 1; });
  return 1;
});
lua.lua_setfield(L, -2, to_luastring('open'));
lua.lua_pop(L, 1);
lua.lua_getglobal(L, to_luastring('os'));
lua.lua_pushcfunction(L, (state) => {
  if (lauxlib.luaL_checkinteger(state, 1) !== 86 || openFiles.size !== 0 || flushes !== 1) {
    return lauxlib.luaL_error(state, to_luastring('breadcrumb was not flushed and closed before termination'));
  }
  process.exit(86);
});
lua.lua_setfield(L, -2, to_luastring('exit'));
lua.lua_pop(L, 1);
lua.lua_newtable(L);
lua.lua_pushstring(L, to_luastring(destination));
lua.lua_rawseti(L, -2, 1);
lua.lua_setglobal(L, to_luastring('arg'));
const script = path.join(import.meta.dirname, 'preflight-failfast.lua');
const loaded = lauxlib.luaL_loadfile(L, to_luastring(script));
if (loaded !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
  console.error(to_jsstring(lua.lua_tostring(L, -1)));
  process.exitCode = 1;
}