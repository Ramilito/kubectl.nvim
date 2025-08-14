use mlua::prelude::*;
use std::sync::{
    mpsc::{channel, Receiver, Sender},
    Mutex, OnceLock,
};

#[derive(Debug)]
struct Event {
    name: String,
    payload: String,
}

static TX: OnceLock<Sender<Event>> = OnceLock::new();
static RX: OnceLock<Mutex<Receiver<Event>>> = OnceLock::new();

fn ensure_channel() {
    if TX.get().is_none() {
        let (tx, rx) = channel::<Event>();
        let _ = TX.set(tx);
        let _ = RX.set(Mutex::new(rx));
    }
}

pub fn notify_named<N: Into<String>, P: Into<String>>(name: N, payload: P) -> bool {
    if let Some(tx) = TX.get() {
        let _ = tx.send(Event {
            name: name.into(),
            payload: payload.into(),
        });
        true
    } else {
        false
    }
}

pub fn install(lua: &Lua, exports: &LuaTable) -> LuaResult<()> {
    let setup = lua.create_function(|_, ()| {
        ensure_channel();
        Ok(true)
    })?;

    let pop_all = lua.create_function(|lua, ()| {
        let rx = RX
            .get()
            .ok_or_else(|| mlua::Error::RuntimeError("setup() not called".to_string()))?
            .lock()
            .map_err(|_| mlua::Error::RuntimeError("rx poisoned".to_string()))?;

        let out = lua.create_table()?;
        for (i, ev) in rx.try_iter().enumerate() {
            let t = lua.create_table()?;
            t.set("name", ev.name)?;
            t.set("payload", ev.payload)?;
            out.set(i + 1, t)?;
        }
        Ok(out)
    })?;

    let emit = lua.create_function(|_, (name, payload): (String, String)| {
        ensure_channel();
        Ok(notify_named(name, payload))
    })?;

    exports.set("setup", setup)?;
    exports.set("pop_all", pop_all)?;
    exports.set("emit", emit)?;
    Ok(())
}
