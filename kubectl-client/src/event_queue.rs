// src/event_queue.rs
// Minimal named-event queue for Neovim.
// - Background Rust code calls `notify_named("pods", payload)`.
// - Lua calls `setup()` once, then `pop_all()` from a tiny timer.
// - No Lua callbacks stored in Rust; callbacks live entirely in Lua (simpler).

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

/// Call from any Rust thread/task (watchers) to enqueue an event for Lua.
pub fn notify_named<N: Into<String>, P: Into<String>>(name: N, payload: P) -> bool {
    if let Some(tx) = TX.get() {
        let _ = tx.send(Event {
            name: name.into(),
            payload: payload.into(),
        });
        true
    } else {
        false // Lua hasn't called setup() yet; decide if you want to log/drop.
    }
}

/// Install functions into the module's export table.
/// Call this from your lib.rs; keep lib.rs logic-free.
pub fn install(lua: &Lua, exports: &LuaTable) -> LuaResult<()> {
    // setup(): initialize the queue once.
    let setup = lua.create_function(|_, ()| {
        ensure_channel();
        Ok(true)
    })?;

    // pop_all(): returns an array of { name = "...", payload = "..." }
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

    // emit(name, payload): convenience for manual testing from Lua.
    let emit = lua.create_function(|_, (name, payload): (String, String)| {
        ensure_channel();
        Ok(notify_named(name, payload))
    })?;

    exports.set("setup", setup)?;
    exports.set("pop_all", pop_all)?;
    exports.set("emit", emit)?;
    Ok(())
}
