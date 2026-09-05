import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = createRequire(require.resolve('fengari-node-cli/package.json'))('fengari');
const root = path.resolve(import.meta.dirname, '..');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const metatable = to_luastring('PedFNameFixture');
let constructorCalls = 0;

function pushName(state, text) {
  const value = lua.lua_newuserdata(state, 1);
  value.text = text;
  lauxlib.luaL_setmetatable(state, metatable);
}

lauxlib.luaL_newmetatable(L, metatable);
lua.lua_pushvalue(L, -1);
lua.lua_setfield(L, -2, to_luastring('__index'));
lua.lua_pushcfunction(L, (state) => {
  lauxlib.luaL_checkudata(state, 1, metatable);
  const text = to_jsstring(lauxlib.luaL_checkstring(state, 2));
  // Lua supplies the callable userdata before the explicit constructor arguments.
  constructorCalls += 1;
  pushName(state, text);
  return 1;
});
lua.lua_setfield(L, -2, to_luastring('__call'));
lua.lua_pushcfunction(L, (state) => {
  const value = lauxlib.luaL_checkudata(state, 1, metatable);
  lua.lua_pushstring(state, to_luastring(value.text));
  return 1;
});
lua.lua_setfield(L, -2, to_luastring('ToString'));
lua.lua_pop(L, 1);
pushName(L, 'None');
lua.lua_setglobal(L, to_luastring('fixture_fname_constructor'));
lua.lua_pushstring(L, to_luastring(`${path.join(root, 'Scripts', '?.lua')};${path.join(root, 'Scripts', '?', 'init.lua')};`));
lua.lua_setglobal(L, to_luastring('fixture_package_path'));
lua.lua_pushstring(L, to_luastring(path.join(root, 'tests', 'admin-control.lua')));
lua.lua_setglobal(L, to_luastring('fixture_admin_tests'));

try {
  const source = `
    package.path = fixture_package_path .. package.path
    assert(type(fixture_fname_constructor) == "userdata")
    local ok, name = pcall(fixture_fname_constructor, "Fixture_Bounty", 1)
    assert(ok and type(name) == "userdata" and name:ToString() == "Fixture_Bounty")
    local count = 0
    local function equal(actual, expected, message)
      assert(actual == expected, message or string.format("expected %s, got %s", tostring(expected), tostring(actual)))
    end
    dofile(fixture_admin_tests)(function(name, callback)
      if name == "nearest native RPC uses only the validated requester and stock group" then
        callback()
        count = count + 1
      end
    end, equal, assert, fixture_fname_constructor)
    assert(count == 1, "native FName binding regression did not run")
  `;
  const loaded = lauxlib.luaL_loadstring(L, to_luastring(source));
  if (loaded !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    const error = lua.lua_tostring(L, -1);
    throw new Error(error ? to_jsstring(error) : 'non-string FName fixture failure');
  }
  if (constructorCalls !== 2) throw new Error('FName construction was skipped or retried');
  console.log('PASS callable FName userdata works through pcall and the scoped native RPC; construction failure locks further calls');
} finally {
  lua.lua_close(L);
}
