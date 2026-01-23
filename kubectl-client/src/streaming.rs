//! Streaming session abstraction for async I/O channels.
//!
//! Provides a unified interface for managing async communication channels
//! used by exec sessions, log streaming, and other I/O-bound operations.

use std::sync::{
    atomic::{AtomicBool, AtomicUsize, Ordering},
    Arc, Mutex, MutexGuard, PoisonError,
};
use tokio::sync::mpsc;

/// A streaming session that manages async I/O over unbounded channels.
///
/// Supports both unidirectional (receive-only) and bidirectional communication.
/// Tracks active tasks and provides lifecycle management.
pub struct StreamingSession<T: Send + 'static> {
    sender: mpsc::UnboundedSender<T>,
    receiver: Mutex<mpsc::UnboundedReceiver<T>>,
    is_active: Arc<AtomicBool>,
    active_task_count: Arc<AtomicUsize>,
}

impl<T: Send + 'static> StreamingSession<T> {
    /// Create a new streaming session.
    pub fn new() -> Self {
        let (sender, receiver) = mpsc::unbounded_channel();
        Self {
            sender,
            receiver: Mutex::new(receiver),
            is_active: Arc::new(AtomicBool::new(true)),
            active_task_count: Arc::new(AtomicUsize::new(0)),
        }
    }

    /// Get a clone of the sender for use in async tasks.
    pub fn sender(&self) -> mpsc::UnboundedSender<T> {
        self.sender.clone()
    }

    /// Get a task handle for spawning tracked async tasks.
    pub fn task_handle(&self) -> TaskHandle {
        TaskHandle {
            is_active: self.is_active.clone(),
            active_task_count: self.active_task_count.clone(),
        }
    }

    /// Try to receive a single message without blocking.
    pub fn try_recv(&self) -> Result<Option<T>, RecvError> {
        let mut receiver = self.lock_receiver()?;
        match receiver.try_recv() {
            Ok(msg) => Ok(Some(msg)),
            Err(mpsc::error::TryRecvError::Empty) => Ok(None),
            Err(mpsc::error::TryRecvError::Disconnected) => Ok(None),
        }
    }

    /// Try to receive up to `limit` messages without blocking.
    pub fn try_recv_batch(&self, limit: usize) -> Result<Vec<T>, RecvError> {
        let mut receiver = self.lock_receiver()?;
        let mut messages = Vec::with_capacity(limit.min(64));

        while messages.len() < limit {
            match receiver.try_recv() {
                Ok(msg) => messages.push(msg),
                Err(_) => break,
            }
        }

        Ok(messages)
    }

    /// Check if the session is still active.
    pub fn is_open(&self) -> bool {
        self.is_active.load(Ordering::Acquire)
    }

    /// Close the session, signaling all tasks to stop.
    pub fn close(&self) {
        self.is_active.store(false, Ordering::Release);
    }

    fn lock_receiver(&self) -> Result<MutexGuard<'_, mpsc::UnboundedReceiver<T>>, RecvError> {
        self.receiver.lock().map_err(|_| RecvError::LockPoisoned)
    }
}

impl<T: Send + 'static> Default for StreamingSession<T> {
    fn default() -> Self {
        Self::new()
    }
}

/// Handle for spawning and tracking async tasks.
///
/// When a task is spawned via this handle, it automatically:
/// - Increments the active task count
/// - Decrements the count when the task completes
/// - Sets is_active to false when the last task completes
#[derive(Clone)]
pub struct TaskHandle {
    is_active: Arc<AtomicBool>,
    active_task_count: Arc<AtomicUsize>,
}

impl TaskHandle {
    /// Check if the session is still active.
    pub fn is_active(&self) -> bool {
        self.is_active.load(Ordering::Acquire)
    }

    /// Force the session to close, regardless of active tasks.
    /// Use this when the underlying process has exited.
    pub fn force_close(&self) {
        self.is_active.store(false, Ordering::Release);
    }

    /// Increment the active task count.
    /// Call this when spawning a new task.
    pub fn task_started(&self) {
        self.active_task_count.fetch_add(1, Ordering::SeqCst);
    }

    /// Decrement the active task count.
    /// If this was the last task, marks the session as inactive.
    pub fn task_completed(&self) {
        let remaining = self.active_task_count.fetch_sub(1, Ordering::SeqCst) - 1;
        if remaining == 0 {
            self.is_active.store(false, Ordering::Release);
        }
    }

    /// Create a guard that automatically calls task_completed when dropped.
    pub fn guard(&self) -> TaskGuard {
        self.task_started();
        TaskGuard {
            handle: self.clone(),
        }
    }
}

/// RAII guard that decrements task count when dropped.
pub struct TaskGuard {
    handle: TaskHandle,
}

impl Drop for TaskGuard {
    fn drop(&mut self) {
        self.handle.task_completed();
    }
}

/// Error type for receive operations.
#[derive(Debug)]
pub enum RecvError {
    LockPoisoned,
}

impl std::fmt::Display for RecvError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RecvError::LockPoisoned => write!(f, "receiver lock poisoned"),
        }
    }
}

impl std::error::Error for RecvError {}

impl<T> From<PoisonError<T>> for RecvError {
    fn from(_: PoisonError<T>) -> Self {
        RecvError::LockPoisoned
    }
}

/// Builder for creating bidirectional streaming sessions.
/// Used for exec-style sessions that need both input and output channels.
pub struct BidirectionalSession<TIn: Send + 'static, TOut: Send + 'static> {
    /// Channel for sending input to the remote process
    pub input: mpsc::UnboundedSender<TIn>,
    input_receiver: mpsc::UnboundedReceiver<TIn>,
    /// Channel for receiving output from the remote process
    pub output: StreamingSession<TOut>,
}

impl<TIn: Send + 'static, TOut: Send + 'static> BidirectionalSession<TIn, TOut> {
    /// Create a new bidirectional session.
    pub fn new() -> Self {
        let (input_sender, input_receiver) = mpsc::unbounded_channel();
        Self {
            input: input_sender,
            input_receiver,
            output: StreamingSession::new(),
        }
    }

    /// Take the input receiver for use in an async writer task.
    /// Can only be called once.
    pub fn take_input_receiver(&mut self) -> Option<mpsc::UnboundedReceiver<TIn>> {
        // Use std::mem::replace to take ownership
        let receiver = std::mem::replace(
            &mut self.input_receiver,
            mpsc::unbounded_channel().1, // Replace with a dummy receiver
        );
        Some(receiver)
    }

    /// Send input to the remote process.
    pub fn send_input(&self, msg: TIn) -> Result<(), mpsc::error::SendError<TIn>> {
        self.input.send(msg)
    }

    /// Try to receive output without blocking.
    pub fn try_recv_output(&self) -> Result<Option<TOut>, RecvError> {
        self.output.try_recv()
    }

    /// Check if the session is still active.
    pub fn is_open(&self) -> bool {
        self.output.is_open()
    }

    /// Close the session.
    pub fn close(&self) {
        self.output.close();
    }

    /// Get the output sender for async tasks.
    pub fn output_sender(&self) -> mpsc::UnboundedSender<TOut> {
        self.output.sender()
    }

    /// Get a task handle for the output session.
    pub fn task_handle(&self) -> TaskHandle {
        self.output.task_handle()
    }
}

impl<TIn: Send + 'static, TOut: Send + 'static> Default for BidirectionalSession<TIn, TOut> {
    fn default() -> Self {
        Self::new()
    }
}
