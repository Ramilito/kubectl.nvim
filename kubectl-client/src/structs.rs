use mlua::{FromLua, Lua, Result as LuaResult, Value as LuaValue};
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Gvk {
    pub k: String,
    pub v: String,
    pub g: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GetAllArgs {
    pub gvk: Gvk,
    pub namespace: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GetTableArgs {
    pub gvk: Gvk,
    pub namespace: Option<String>,
    pub sort_by: Option<String>,
    pub sort_order: Option<String>,
    pub filter: Option<String>,
    pub filter_label: Option<Vec<String>>,
    pub filter_key: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StartReflectorArgs {
    pub gvk: Gvk,
    pub namespace: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GetServerRawArgs {
    pub path: String,
}

#[derive(Clone, Deserialize)]
pub struct GetSingleArgs {
    pub gvk: Gvk,
    pub name: String,
    pub namespace: Option<String>,
    pub output: Option<String>,
    pub cached: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CmdEditArgs {
    pub path: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CmdDeleteArgs {
    pub gvk: Gvk,
    pub name: String,
    pub namespace: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CmdRestartArgs {
    pub gvk: Gvk,
    pub name: String,
    pub namespace: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CmdScaleArgs {
    pub gvk: Gvk,
    pub name: String,
    pub namespace: String,
    pub replicas: usize,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GetFallbackTableArgs {
    pub gvk: Gvk,
    pub namespace: Option<String>,
    pub sort_by: Option<String>,
    pub sort_order: Option<String>,
    pub filter: Option<String>,
    pub filter_label: Option<Vec<String>>,
    pub filter_key: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct GetMinifiedConfig {
    pub ctx_override: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CmdDescribeArgs {
    pub name: String,
    pub namespace: Option<String>,
    pub context: String,
    pub gvk: Gvk,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PodRef {
    pub name: String,
    pub namespace: String,
}

/// Unified configuration for log streaming and fetching.
/// Used by both real-time streaming (follow mode) and one-shot fetches.
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct LogConfig {
    /// Target pods to fetch logs from
    pub pods: Vec<PodRef>,
    /// Target container name (None = all containers)
    pub container: Option<String>,
    /// Duration string like "5m", "1h" for historical logs
    pub since: Option<String>,
    /// If true, fetch logs from the previous container instance
    pub previous: Option<bool>,
    /// Include timestamps in log output
    pub timestamps: Option<bool>,
    /// Force prefix behavior: Some(true) = always, Some(false) = never, None = auto
    pub prefix: Option<bool>,
    /// If true, streams continuously; if false, one-shot fetch
    pub follow: Option<bool>,
    /// Number of histogram buckets (for one-shot fetch display)
    pub histogram_width: Option<usize>,
}

impl FromLua for LogConfig {
    fn from_lua(value: LuaValue, _lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(t) => {
                let pods: Vec<mlua::Table> = t.get("pods")?;
                let pods = pods
                    .into_iter()
                    .map(|p| {
                        Ok(PodRef {
                            name: p.get("name")?,
                            namespace: p.get("namespace")?,
                        })
                    })
                    .collect::<LuaResult<Vec<_>>>()?;

                Ok(LogConfig {
                    pods,
                    container: t.get("container")?,
                    since: t.get("since")?,
                    previous: t.get("previous")?,
                    timestamps: t.get("timestamps")?,
                    prefix: t.get("prefix")?,
                    follow: t.get("follow")?,
                    histogram_width: t.get("histogram_width")?,
                })
            }
            _ => Err(mlua::Error::FromLuaConversionError {
                from: value.type_name(),
                to: "LogConfig".to_string(),
                message: Some("expected table".to_string()),
            }),
        }
    }
}

#[derive(Debug, Clone)]
pub struct ImageSpec {
    pub name: String,
    pub image: String,
    pub init: bool,
}

impl FromLua for ImageSpec {
    fn from_lua(value: LuaValue, _lua: &Lua) -> LuaResult<Self> {
        match value {
            LuaValue::Table(t) => {
                let name: String = t.get("name")?;
                let image: String = t.get("image")?;
                let init: bool = t.get("init")?;
                Ok(ImageSpec { name, image, init })
            }
            _ => Err(mlua::Error::FromLuaConversionError {
                from: value.type_name(),
                to: "ImageSpec".to_string(),
                message: None,
            }),
        }
    }
}
