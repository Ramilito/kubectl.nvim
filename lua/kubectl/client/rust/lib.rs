use futures::StreamExt;
use kube::config::KubeConfigOptions;
use kube::runtime::watcher;
use kube::runtime::watcher::Event;
use kube::{Client, Config};
use mlua::prelude::*;
use std::sync::Mutex;
use tokio::runtime::Runtime;


static RUNTIME: Mutex<Option<Runtime>> = Mutex::new(None);
static CLIENT_INSTANCE: Mutex<Option<Client>> = Mutex::new(None);

mod store;
fn init_runtime(_lua: &Lua, context_name: Option<String>) -> LuaResult<bool> {
    let mut rt_guard = RUNTIME.lock().unwrap();
    let mut client_guard = CLIENT_INSTANCE.lock().unwrap();

    let new_rt = Runtime::new().expect("Failed to create Tokio runtime");
    let new_client = new_rt.block_on(async {
        let options = KubeConfigOptions {
            context: context_name.clone(),
            cluster: None,
            user: None,
        };
        let config = Config::from_kubeconfig(&options)
            .await
            .expect("Failed to load kubeconfig");
        Client::try_from(config).expect("Failed to create Kubernetes client")
    });

    *rt_guard = Some(new_rt);
    *client_guard = Some(new_client);
    Ok(true)
}

fn strip_managed_fields(obj: &mut kube::api::DynamicObject) {
    obj.metadata.managed_fields = None;
}

fn get_resource(
    _lua: &Lua,
    (resource, group, version, name, namespace, _sortby): (
        String,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> LuaResult<String> {
    let rt_guard = RUNTIME.lock().unwrap();
    let client_guard = CLIENT_INSTANCE.lock().unwrap();
    let rt = rt_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Runtime not initialized".into()))?;
    let client = client_guard
        .as_ref()
        .ok_or_else(|| mlua::Error::RuntimeError("Client not initialized".into()))?;

    let group_str = group.unwrap_or_default();
    let version_str = version.unwrap_or_else(|| "v1".to_string());
    let gvk = kube::core::GroupVersionKind {
        group: group_str,
        version: version_str,
        kind: resource.clone(),
    };
    let ar = kube::api::ApiResource::from_gvk(&gvk);
    let api = if let Some(ns) = namespace.clone() {
        kube::api::Api::<kube::api::DynamicObject>::namespaced_with(client.clone(), &ns, &ar)
    } else {
        kube::api::Api::<kube::api::DynamicObject>::all_with(client.clone(), &ar)
    };

    // Use the correct watcher config instead of ListParams.
    let watcher_config = kube::runtime::watcher::Config::default();

    let mut items = rt
        .block_on(async {
            if let Some(n) = name {
                Ok(vec![api.get(&n).await?])
            } else {
                Ok(api.list(&kube::api::ListParams::default()).await?.items)
            }
        })
        .map_err(|e: kube::Error| mlua::Error::RuntimeError(e.to_string()))?;

    // Strip managedFields before storing in the database.
    for item in &mut items {
        strip_managed_fields(item);
    }
    // Store the fetched items keyed by the resource kind.
    store::set(&resource, items.clone());

    // Spawn a watcher to keep the store up-to-date.
    let api_watcher = if let Some(ns) = namespace {
        kube::api::Api::<kube::api::DynamicObject>::namespaced_with(client.clone(), &ns, &ar)
    } else {
        kube::api::Api::<kube::api::DynamicObject>::all_with(client.clone(), &ar)
    };
    let kind_clone = resource.clone();
    rt.spawn(async move {
        let mut watcher_stream = watcher(api_watcher, watcher_config).boxed();
        while let Some(event) = watcher_stream.next().await {
            match event {
                Ok(Event::Apply(obj)) => {
                    store::update(&kind_clone, obj);
                },
                Ok(Event::Delete(obj)) => {
                    store::delete(&kind_clone, &obj);
                },
                _ => {},
            }
        }
    });

    let json_str = k8s_openapi::serde_json::to_string(&items)
        .map_err(|e| mlua::Error::RuntimeError(e.to_string()))?;
    Ok(json_str)
}

fn get_store(_lua: &Lua, key: String) -> LuaResult<String> {
    if let Some(json_str) = store::to_json(&key) {
        Ok(json_str)
    } else {
        Err(mlua::Error::RuntimeError("No data for given key".into()))
    }
}

#[mlua::lua_module(skip_memory_check)]
fn kubectl_client(lua: &Lua) -> LuaResult<mlua::Table> {
    let exports = lua.create_table()?;
    exports.set("init_runtime", lua.create_function(init_runtime)?)?;
    exports.set("get_resource", lua.create_function(get_resource)?)?;
    exports.set("get_store", lua.create_function(get_store)?)?;
    Ok(exports)
}
