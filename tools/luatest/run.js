// Headless harness: runs RFTelem under fengari (Lua 5.3) with EdgeTX API
// stubs. Usage: node run.js <main.lua> <driver.lua> [args...]
// Globals for the driver: MAIN_SRC (the main file), ARGS, FILES (every
// .lua in the widget folder as "/WIDGETS/RFTelem/<name>", and this folder's
// .lua files as "/luatest/<name>") so loadScript() can be stubbed.
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const [mainPath, driverPath, ...args] = process.argv.slice(2);
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

lua.lua_pushstring(L, to_luastring(fs.readFileSync(mainPath, 'utf8')));
lua.lua_setglobal(L, to_luastring('MAIN_SRC'));
lua.lua_pushstring(L, to_luastring(args.join(' ')));
lua.lua_setglobal(L, to_luastring('ARGS'));

lua.lua_newtable(L);
function addDir(dir, prefix) {
  for (const name of fs.readdirSync(dir)) {
    if (!name.endsWith('.lua')) continue;
    lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(dir, name), 'utf8')));
    lua.lua_setfield(L, -2, to_luastring(prefix + name));
  }
}
addDir(path.dirname(path.resolve(mainPath)), '/WIDGETS/RFTelem/');
addDir(__dirname, '/luatest/');
lua.lua_setglobal(L, to_luastring('FILES'));

const driver = fs.readFileSync(driverPath, 'utf8');
if (lauxlib.luaL_loadbuffer(L, to_luastring(driver), null, to_luastring('driver')) !== lua.LUA_OK ||
    lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
  console.error('LUA ERROR: ' + lua.lua_tojsstring(L, -1));
  process.exit(1);
}
