local hl = require("kubectl.actions.highlight")
local M = {}

--- Color a status based on its severity
---@param status string
---@return string
function M.ColorStatus(status)
  local errorStatuses = {
    Red = true,
    Failed = true,
    BackOff = true,
    ExceededGracePeriod = true,
    FailedKillPod = true,
    FailedCreatePodContainer = true,
    NetworkNotReady = true,
    InspectFailed = true,
    ErrImageNeverPull = true,
    NodeNotSchedulable = true,
    KubeletSetupFailed = true,
    FailedAttachVolume = true,
    FailedMount = true,
    VolumeResizeFailed = true,
    FileSystemResizeFailed = true,
    FailedMapVolume = true,
    ContainerGCFailed = true,
    ImageGCFailed = true,
    FailedNodeAllocatableEnforcement = true,
    FailedCreatePodSandBox = true,
    FailedPodSandBoxStatus = true,
    FailedMountOnFilesystemMismatch = true,
    InvalidDiskCapacity = true,
    FreeDiskSpaceFailed = true,
    SecretSyncedError = true,
    Unhealthy = true,
    FailedSync = true,
    FailedValidation = true,
    FailedPostStartHook = true,
    FailedPreStopHook = true,
    NotReady = true,
    NetworkUnavailable = true,
    ContainerStatusUnknown = true,
    CrashLoopBackOff = true,
    ImagePullBackOff = true,
    Evicted = true,
    FailedScheduling = true,
    Error = true,
    ErrImagePull = true,
    OOMKilled = true,
    Lost = true,
    Unknown = true,
  }

  local warningStatuses = {
    Yellow = true,
    Killing = true,
    Preempting = true,
    Pulling = true,
    NodeNotReady = true,
    NodeSchedulable = true,
    Starting = true,
    AlreadyMountedVolume = true,
    SuccessfulAttachVolume = true,
    SuccessfulMountVolume = true,
    NodeAllocatableEnforced = true,
    ProbeWarning = true,
    Pending = true,
    ContainerCreating = true,
    PodInitializing = true,
    Terminating = true,
    Terminated = true,
    Warning = true,
    Delete = true,
    Available = true,
    Released = true,
    ScalingReplicaSet = true,
  }

  local successStatuses = {
    Green = true,
    Running = true,
    Completed = true,
    Pulled = true,
    Created = true,
    Rebooted = true,
    NodeReady = true,
    Started = true,
    Normal = true,
    VolumeResizeSuccessful = true,
    FileSystemResizeSuccessful = true,
    SecretSynced = true,
    Ready = true,
    Scheduled = true,
    SuccessfulCreate = true,
    Retain = true,
    Bound = true,

    -- Custom statuses
    Active = true,
    True = true,
  }

  local capitalized = status:gsub("^%l", string.upper)
  if errorStatuses[capitalized] then
    return hl.symbols.error
  elseif warningStatuses[capitalized] then
    return hl.symbols.warning
  elseif successStatuses[capitalized] then
    return hl.symbols.success
  else
    return ""
  end
end

return M
