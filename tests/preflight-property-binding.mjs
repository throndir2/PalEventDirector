import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = createRequire(require.resolve('fengari-node-cli/package.json'))('fengari');
const root = path.resolve(import.meta.dirname, '..');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
let propertyCount = 2;
let callbacks = 0;
let invalidCleanup = false;

const iterate = (state) => {
  if (!lua.lua_isuserdata(state, 1)) {
    return lauxlib.luaL_error(state, to_luastring('A function requiring userdata as param #1 was called without userdata at param #1'));
  }
  // Pinned LuaMadeSimple::get_userdata consumes the receiver, not a bound upvalue.
  lua.lua_remove(state, 1);
  for (let index = 1; index <= propertyCount; index += 1) {
    lua.lua_pushvalue(state, 1);
    lua.lua_pushinteger(state, index);
    callbacks += 1;
    if (lua.lua_pcall(state, 1, 1, 0) !== lua.LUA_OK) return lua.lua_error(state);
    let stop = false;
    if (lua.lua_isboolean(state, 2)) {
      stop = lua.lua_toboolean(state, 2);
      lua.lua_remove(state, 2); // Pinned Lua::get_bool consumes its value.
    }
    if (stop) break;
    // The pinned iterator also discards index 2 on continuation. Detect an invalid
    // index instead of asking the test VM to execute an undefined stack operation.
    if (lua.lua_gettop(state) < 2) {
      invalidCleanup = true;
      return lauxlib.luaL_error(state, to_luastring('pinned iterator callback cleanup has no result at index 2'));
    }
    lua.lua_remove(state, 2);
  }
  return 1;
};

lua.lua_newuserdata(L, 1);
lua.lua_newtable(L);
lua.lua_newtable(L);
lua.lua_pushcfunction(L, iterate);
lua.lua_setfield(L, -2, to_luastring('ForEachProperty'));
lua.lua_setfield(L, -2, to_luastring('__index'));
lua.lua_setmetatable(L, -2);
lua.lua_setglobal(L, to_luastring('owner'));
lua.lua_pushstring(L, to_luastring(`${path.join(root, 'Scripts', '?.lua')};${path.join(root, 'Scripts', '?', 'init.lua')};`));
lua.lua_setglobal(L, to_luastring('fixture_package_path'));

function execute(source) {
  const loaded = lauxlib.luaL_loadstring(L, to_luastring(source));
  if (loaded !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    const error = lua.lua_tostring(L, -1);
    throw new Error(error ? to_jsstring(error) : 'non-string fixture failure');
  }
}

try {
  execute(`
    local ok, reason = pcall(function() owner.ForEachProperty(function() end) end)
    assert(not ok and reason:find("requiring userdata", 1, true))
    ok, reason = pcall(function() owner:ForEachProperty(function() return false end) end)
    assert(not ok and reason:find("cleanup has no result at index 2", 1, true))
  `);
  if (!invalidCleanup) throw new Error('false-continuation control did not reproduce the pinned cleanup hazard');

  for (const continuation of ['nil', 'true']) {
    callbacks = 0;
    invalidCleanup = false;
    execute(`owner:ForEachProperty(function() return ${continuation} end)`);
    if (invalidCleanup || callbacks !== (continuation === 'nil' ? 2 : 1)) {
      throw new Error('nil continuation / Boolean early-stop contract failed');
    }
  }
  console.log('PASS pinned receiver requirement and false-result double removal reproduced; nil/true paths preserve the stack');

  for (const count of [2, 5]) {
    propertyCount = count;
    callbacks = 0;
    invalidCleanup = false;
    lua.lua_pushinteger(L, count);
    lua.lua_setglobal(L, to_luastring('fixture_property_count'));
    execute(`
      package.path = fixture_package_path .. package.path
      local Diagnostic = require("ped.preflight_diagnostic")
      local Config = require("ped.config")
      local records = {}
      local env = {
        COMPUTERNAME = "IMOUTO", PAL_EVENT_DIRECTOR_SERVER_BUILD_ID = "24575149",
        PAL_EVENT_DIRECTOR_UE4SS_TAG = "2281fa31", PAL_EVENT_DIRECTOR_UE4SS_API_VERSION = "3.0.1",
      }
      local diagnostic = Diagnostic.new({
        config = Config.defaults(), run_id = 100, engine = {},
        getenv = function(name) return env[name] end,
        record = function(step) records[#records + 1] = step; return true end,
      })
      local observed
      diagnostic.thread = coroutine.create(function()
        observed = diagnostic:_properties("fixture", owner, 2)
        diagnostic:_stop("fixture complete")
      end)
      local reason
      for _ = 1, 3 do
        assert(diagnostic:run())
        local ok
        ok, reason = diagnostic:run("confirm-disposable-readonly", diagnostic.pending.step)
        if not ok then break end
      end
      assert(diagnostic.halted)
      assert(not reason:find("raw error suppressed", 1, true), reason)
      if fixture_property_count == 2 then
        assert(reason == "fixture complete" and #observed == 2, reason)
      else
        assert(reason:find("Unexpected property inventory", 1, true) and observed == nil, reason)
      end
      assert(#records == 4)
      assert(records[1]:match("properties%-method.before$"))
      assert(records[2]:match("properties%-method.after$"))
      assert(records[3]:match("properties.before$"))
      assert(records[4]:match("properties.after$"))
    `);
    if (invalidCleanup || callbacks !== Math.min(count, 3)) throw new Error('diagnostic failed bounded stack-safe iteration');
  }
  console.log('PASS actual diagnostic helper preserves the receiver, callback stack, enumeration limit and separate breadcrumbs');
} finally {
  lua.lua_close(L);
}
