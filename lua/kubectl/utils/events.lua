local hl = require("kubectl.actions.highlight")
local string_utils = require("kubectl.utils.string")
local M = {}

--- Color a status based on its severity
---@param status string
---@return string
function M.ColorStatus(status)
  local errorStatuses = {
    Red = true,
    Error = true,

    BackOff = true,
    ContainerGCFailed = true,
    ContainerStatusUnknown = true,
    CrashLoopBackOff = true,
    DeadlineExceeded = true,
    Degraded = true,
    ErrImageNeverPull = true,
    ErrImagePull = true,
    Evicted = true,
    ExceededGracePeriod = true,
    Failed = true,
    FailedAttachVolume = true,
    FailedCreatePodContainer = true,
    FailedCreatePodSandBox = true,
    FailedDeclare = true,
    FailedKillPod = true,
    FailedMapVolume = true,
    FailedMount = true,
    FailedMountOnFilesystemMismatch = true,
    FailedNodeAllocatableEnforcement = true,
    FailedPodSandBoxStatus = true,
    FailedPostStartHook = true,
    FailedPreStopHook = true,
    FailedScheduling = true,
    FailedSync = true,
    FailedToUpdateEndpoint = true,
    FailedToUpdateEndpointSlices = true,
    FailedValidation = true,
    FileSystemResizeFailed = true,
    FreeDiskSpaceFailed = true,
    ImageGCFailed = true,
    ImagePullBackOff = true,
    InspectFailed = true,
    InvalidDiskCapacity = true,
    InvalidImageName = true,
    KubeletSetupFailed = true,
    Lost = true,
    NetworkUnavailable = true,
    NodeNotSchedulable = true,
    OOMKilled = true,
    OutOfpods = true,
    SecretSyncedError = true,
    Unhealthy = true,
    Unknown = true,
    UpdateFailed = true,
    VolumeResizeFailed = true,
    ["Init:ErrImagePull"] = true,
    ["Init:ImagePullBackOff"] = true,
    ["Init:ContainerStatusUnknown"] = true,
  }

  local warningStatuses = {
    Yellow = true,
    Warning = true,

    AlreadyMountedVolume = true,
    Available = true,
    ContainerCreating = true,
    Delete = true,
    DeletingNode = true,
    EvictedByVPA = true,
    Killing = true,
    NetworkNotReady = true,
    NodeAllocatableEnforced = true,
    NodeNotReady = true,
    NodeSchedulable = true,
    NotReady = true,
    OutOfSync = true,
    Pending = true,
    PodInitializing = true,
    Preempting = true,
    ProbeWarning = true,
    Progressing = true,
    Pulling = true,
    Released = true,
    RemovingNode = true,
    ScalingReplicaSet = true,
    Starting = true,
    SuccessfulAttachVolume = true,
    SuccessfulMountVolume = true,
    Terminated = true,
    Terminating = true,
  }

  local successStatuses = {
    Green = true,
    Success = true,

    Active = true,
    Bound = true,
    Completed = true,
    Created = true,
    Deployed = true,
    FileSystemResizeSuccessful = true,
    Healthy = true,
    NodeHasNoDiskPressure = true,
    NodeHasSufficientMemory = true,
    NodeHasSufficientPID = true,
    NodeReady = true,
    Normal = true,
    Pulled = true,
    Ready = true,
    Rebooted = true,
    RegisteredNode = true,
    Retain = true,
    Running = true,
    SawCompletedJob = true,
    Scheduled = true,
    SecretSynced = true,
    Started = true,
    SuccessfulCreate = true,
    SuccessfulDeclare = true,
    SuccessfulDelete = true,
    SuccessfulRescale = true,
    SuccessfulUpdate = true,
    SuccessfullyReconciled = true,
    Synced = true,
    True = true,
    Updated = true,
    UpdatedLoadBalancer = true,
    Valid = true,
    VolumeResizeSuccessful = true,
  }

  if type(status) ~= "string" then
    return ""
  end
  local capitalized = string_utils.capitalize(status)
  if errorStatuses[capitalized] then
    return hl.symbols.error
  elseif warningStatuses[capitalized] then
    return hl.symbols.warning
  elseif successStatuses[capitalized] then
    return hl.symbols.success
  end
  return ""
end

local completedStatuses = {
  Completed = true,
  Succeeded = true,
}

--- Get semantic line highlight for a status
---@param status string
---@return string|nil highlight group name or nil for no highlight
function M.GetSemanticHighlight(status)
  if type(status) ~= "string" then
    return nil
  end
  local capitalized = string_utils.capitalize(status)

  -- Completed takes priority (dimmed, not attention-grabbing)
  if completedStatuses[capitalized] then
    return hl.symbols.semantic_completed
  end

  if M.ColorStatus(status) == hl.symbols.error then
    return hl.symbols.semantic_error
  elseif M.ColorStatus(status) == hl.symbols.warning then
    return hl.symbols.semantic_warn
  end

  return nil
end

return M
