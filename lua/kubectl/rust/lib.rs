use mlua::prelude::*;

pub fn test(_: &Lua, text: mlua::String) -> LuaResult<String> {
    println!("test: {:?}", text);

    return Ok("Test".to_string());
}

// NOTE: skip_memory_check greatly improves performance
// https://github.com/mlua-rs/mlua/issues/318
#[mlua::lua_module(skip_memory_check)]
fn blink_cmp_fuzzy(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;
    exports.set("test", lua.create_function(test)?)?;
    Ok(exports)
}
