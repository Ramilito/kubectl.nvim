use std::collections::HashSet;
use std::sync::OnceLock;

/// This struct is analogous to the Lua `M.symbols` table.
/// Each field is a highlight group name (e.g. "KubectlError").
#[derive(Debug)]
pub struct Symbols {
    pub header: String,
    pub warning: String,
    pub error: String,
    pub info: String,
    pub debug: String,
    pub success: String,
    pub pending: String,
    pub deprecated: String,
    pub experimental: String,
    pub gray: String,
    pub white: String,
    pub note: String,
    pub clear: String,
    pub tab: String,
    pub underline: String,
    /// "match" is reserved in Rust, rename to `match_`.
    pub match_: String,
}

/// We store a OnceLock that holds our global `Symbols` instance.
static SYMBOLS: OnceLock<Symbols> = OnceLock::new();

/// Three OnceLock<HashSet<String>> for error, warning, success statuses.
static ERROR_STATUSES: OnceLock<HashSet<String>> = OnceLock::new();
static WARNING_STATUSES: OnceLock<HashSet<String>> = OnceLock::new();
static SUCCESS_STATUSES: OnceLock<HashSet<String>> = OnceLock::new();

/// Provide a function to access the global `Symbols`, initializing it if needed.
pub fn symbols() -> &'static Symbols {
    SYMBOLS.get_or_init(|| Symbols {
        header:       "KubectlHeader".to_string(),
        warning:      "KubectlWarning".to_string(),
        error:        "KubectlError".to_string(),
        info:         "KubectlInfo".to_string(),
        debug:        "KubectlDebug".to_string(),
        success:      "KubectlSuccess".to_string(),
        pending:      "KubectlPending".to_string(),
        deprecated:   "KubectlDeprecated".to_string(),
        experimental: "KubectlExperimental".to_string(),
        gray:         "KubectlGray".to_string(),
        white:        "KubectlWhite".to_string(),
        note:         "KubectlNote".to_string(),
        clear:        "KubectlClear".to_string(),
        tab:          "KubectlTab".to_string(),
        underline:    "KubectlUnderline".to_string(),
        match_:       "KubectlPmatch".to_string(),
    })
}

/// Return a reference to the error status set.
fn error_statuses() -> &'static HashSet<String> {
    ERROR_STATUSES.get_or_init(|| {
        let mut set = HashSet::new();
        // Fill in from your `errorStatuses` table:
        set.insert("Red".into());
        set.insert("Error".into());
        set.insert("Backoff".into());
        set.insert("Containergcfailed".into());
        set.insert("Containerstatusunknown".into());
        set.insert("Crashloopbackoff".into());
        set.insert("Deadlineexceeded".into());
        set.insert("Degraded".into());
        set.insert("Errimageneverpull".into());
        set.insert("Errimagepull".into());
        set.insert("Evicted".into());
        set.insert("Exceededgraceperiod".into());
        set.insert("Failed".into());
        set.insert("Failedattachvolume".into());
        set.insert("Failedcreatepodcontainer".into());
        set.insert("Failedcreatepodsandbox".into());
        set.insert("Faileddeclare".into());
        set.insert("Failedkillpod".into());
        set.insert("Failedmapvolume".into());
        set.insert("Failedmount".into());
        set.insert("Failedmountonfilesystemmismatch".into());
        set.insert("Failednodeallocatableenforcement".into());
        set.insert("Failedpodsandboxstatus".into());
        set.insert("Failedpoststarthook".into());
        set.insert("Failedprestophook".into());
        set.insert("Failedscheduling".into());
        set.insert("Failedsync".into());
        set.insert("Failedtoupdateendpoint".into());
        set.insert("Failedtoupdateendpointslices".into());
        set.insert("Failedvalidation".into());
        set.insert("Filesystemresizefailed".into());
        set.insert("Freediskspacefailed".into());
        set.insert("Imagegcfailed".into());
        set.insert("Imagepullbackoff".into());
        set.insert("Inspectfailed".into());
        set.insert("Invaliddiskcapacity".into());
        set.insert("Invalidimagename".into());
        set.insert("Kubeletsetupfailed".into());
        set.insert("Lost".into());
        set.insert("Networkunavailable".into());
        set.insert("Nodenotschedulable".into());
        set.insert("Oomkilled".into());
        set.insert("Outofpods".into());
        set.insert("Secretsyncederror".into());
        set.insert("Unhealthy".into());
        set.insert("Unknown".into());
        set.insert("Updatefailed".into());
        set.insert("Volumeresizefailed".into());
        // For "Init:ErrImagePull" => after capitalize => "Init:errimagepull"
        set.insert("Init:errimagepull".into());
        set.insert("Init:imagepullbackoff".into());
        set
    })
}

/// Return a reference to the warning status set.
fn warning_statuses() -> &'static HashSet<String> {
    WARNING_STATUSES.get_or_init(|| {
        let mut set = HashSet::new();
        // fill in from your `warningStatuses`
        set.insert("Yellow".into());
        set.insert("Warning".into());
        set.insert("Alreadymountedvolume".into());
        set.insert("Available".into());
        set.insert("Containercreating".into());
        set.insert("Delete".into());
        set.insert("Deletingnode".into());
        set.insert("Evictedbyvpa".into());
        set.insert("Killing".into());
        set.insert("Networknotready".into());
        set.insert("Nodeallocatableenforced".into());
        set.insert("Nodenotready".into());
        set.insert("Nodeschedulable".into());
        set.insert("Notready".into());
        set.insert("Outofsync".into());
        set.insert("Pending".into());
        set.insert("Podinitializing".into());
        set.insert("Preempting".into());
        set.insert("Probewarning".into());
        set.insert("Progressing".into());
        set.insert("Pulling".into());
        set.insert("Released".into());
        set.insert("Removingnode".into());
        set.insert("Scalingreplicaset".into());
        set.insert("Starting".into());
        set.insert("Successfulattachvolume".into());
        set.insert("Successfulmountvolume".into());
        set.insert("Terminated".into());
        set.insert("Terminating".into());
        set
    })
}

/// Return a reference to the success status set.
fn success_statuses() -> &'static HashSet<String> {
    SUCCESS_STATUSES.get_or_init(|| {
        let mut set = HashSet::new();
        // fill in from your `successStatuses`
        set.insert("Green".into());
        set.insert("Success".into());
        set.insert("Active".into());
        set.insert("Bound".into());
        set.insert("Completed".into());
        set.insert("Created".into());
        set.insert("Deployed".into());
        set.insert("Filesystemresizesuccessful".into());
        set.insert("Healthy".into());
        set.insert("Nodehasnodiskpressure".into());
        set.insert("Nodehassufficientmemory".into());
        set.insert("Nodehassufficientpid".into());
        set.insert("Nodeready".into());
        set.insert("Normal".into());
        set.insert("Pulled".into());
        set.insert("Ready".into());
        set.insert("Rebooted".into());
        set.insert("Registerednode".into());
        set.insert("Retain".into());
        set.insert("Running".into());
        set.insert("Sawcompletedjob".into());
        set.insert("Scheduled".into());
        set.insert("Secretsynced".into());
        set.insert("Started".into());
        set.insert("Successfulcreate".into());
        set.insert("Successfuldeclare".into());
        set.insert("Successfuldelete".into());
        set.insert("Successfulrescale".into());
        set.insert("Successfulupdate".into());
        set.insert("Successfullyreconciled".into());
        set.insert("Synced".into());
        set.insert("True".into());
        set.insert("Updated".into());
        set.insert("Updatedloadbalancer".into());
        set.insert("Valid".into());
        set.insert("Volumeresizesuccessful".into());
        set
    })
}

/// Capitalize the first letter and lowercase the rest.
/// Replicates the `string_utils.capitalize(...)` logic from Lua.
fn capitalize(s: &str) -> String {
    if s.is_empty() {
        return "".to_string();
    }
    let mut chars = s.chars();
    let first_char = chars.next().unwrap();
    format!(
        "{}{}",
        first_char.to_uppercase(),
        chars.as_str().to_lowercase()
    )
}

/// Return the appropriate highlight group name for a given `status`.
/// Replicates `M.ColorStatus(status)` in your Lua code.
pub fn color_status(status: &str) -> String {
    if status.is_empty() {
        return "".to_string();
    }
    let capitalized = capitalize(status);

    // Check our sets in order: error, warning, success.
    if error_statuses().contains(&capitalized) {
        symbols().error.clone()
    } else if warning_statuses().contains(&capitalized) {
        symbols().warning.clone()
    } else if success_statuses().contains(&capitalized) {
        symbols().success.clone()
    } else {
        "".to_string()
    }
}
