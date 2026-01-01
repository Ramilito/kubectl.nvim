//! Drift detection command - compares local manifests against cluster state.
//!
//! This module wraps kubediff to provide structured diff results for the Neovim UI.

use mlua::prelude::*;

use crate::block_on;

/// Lua-exposed function to get drift results.
///
/// Arguments:
/// - path: string - Path to the manifest file or directory
/// - hide_unchanged: boolean (optional) - Whether to filter out unchanged resources
///
/// Returns a table with:
/// - entries: array of {kind, name, status, diff, error, diff_lines}
/// - counts: {changed, unchanged, errors}
/// - build_error: string or nil
pub fn get_drift(lua: &Lua, (path, hide_unchanged): (String, Option<bool>)) -> LuaResult<LuaTable> {
    let hide = hide_unchanged.unwrap_or(false);

    // Early return for empty path
    if path.is_empty() {
        let result = lua.create_table()?;
        result.set("entries", lua.create_table()?)?;

        let counts = lua.create_table()?;
        counts.set("changed", 0)?;
        counts.set("unchanged", 0)?;
        counts.set("errors", 0)?;
        result.set("counts", counts)?;

        result.set("build_error", mlua::Value::Nil)?;
        return Ok(result);
    }

    // Call kubediff
    let target_result = block_on(async {
        let client = kubediff::KubeClient::new()
            .await
            .map_err(|e| LuaError::RuntimeError(e.to_string()))?;
        Ok::<_, LuaError>(kubediff::Process::process_target(&client, &path).await)
    })?;

    let result = lua.create_table()?;

    // Handle build errors
    if let Some(error) = target_result.build_error {
        result.set("entries", lua.create_table()?)?;

        let counts = lua.create_table()?;
        counts.set("changed", 0)?;
        counts.set("unchanged", 0)?;
        counts.set("errors", 0)?;
        result.set("counts", counts)?;

        result.set("build_error", error)?;
        return Ok(result);
    }

    // Process results and build entries
    let entries = lua.create_table()?;
    let mut changed_count: usize = 0;
    let mut unchanged_count: usize = 0;
    let mut error_count: usize = 0;
    let mut entry_idx: usize = 1;

    for diff_result in target_result.results {
        let (status, diff_lines) = if diff_result.error.is_some() {
            error_count += 1;
            ("error", 0)
        } else if diff_result.diff.is_some() {
            changed_count += 1;
            let lines = diff_result.diff.as_ref().map_or(0, |d| d.lines().count());
            ("changed", lines)
        } else {
            unchanged_count += 1;
            ("unchanged", 0)
        };

        // Filter unchanged if requested
        if hide && status == "unchanged" {
            continue;
        }

        let entry = lua.create_table()?;
        entry.set("kind", diff_result.kind.as_str())?;
        entry.set("name", diff_result.resource_name.as_str())?;
        entry.set("status", status)?;

        if let Some(ref diff) = diff_result.diff {
            entry.set("diff", diff.as_str())?;
        } else {
            entry.set("diff", mlua::Value::Nil)?;
        }

        if let Some(ref err) = diff_result.error {
            entry.set("error", err.as_str())?;
        } else {
            entry.set("error", mlua::Value::Nil)?;
        }

        entry.set("diff_lines", diff_lines)?;

        entries.set(entry_idx, entry)?;
        entry_idx += 1;
    }

    result.set("entries", entries)?;

    // Build counts (always include all counts, not filtered)
    let counts = lua.create_table()?;
    counts.set("changed", changed_count)?;
    counts.set("unchanged", unchanged_count)?;
    counts.set("errors", error_count)?;
    result.set("counts", counts)?;

    result.set("build_error", mlua::Value::Nil)?;

    Ok(result)
}
