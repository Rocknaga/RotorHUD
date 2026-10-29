// Headless harness: runs RFTelem main.lua under fengari (Lua 5.3) with
// EdgeTX API stubs. Usage: node run.js <main.lua> <driver.lua> [args...]
const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const [mainPath, driverPath, ...args] = process.argv.slice(2);
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

lua.lua_pushstring(L, to_luastring(fs.readFileSync(mainPath, 'utf8')));
lua.lua_setglobal(L, to_luastring('MAIN_SRC'));
lua.lua_pushstring(L, to_luastring(args.join(' ')));
lua.lua_setglobal(L, to_luastring('ARGS'));

const driver = fs.readFileSync(driverPath, 'utf8');
if (lauxlib.luaL_loadbuffer(L, to_luastring(driver), null, to_luastring('driver')) !== lua.LUA_OK ||
    lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
  console.error('LUA ERROR: ' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}
