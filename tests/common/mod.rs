// Shared fixtures for the integration tests. One copy here, so every test
// builds the same fixture; a helper duplicated across test files drifts,
// and each drift is a flake.
//
// Not every test file uses every helper, and each file is its own crate.
#![allow(dead_code)]

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use tempfile::TempDir;

/// A scratch directory that is deleted when the fixture is dropped,
/// whether the test passed or panicked. The `TempDir` field is what ties
/// cleanup to the struct; `tempfile::tempdir()?.path()` in one expression
/// is a path to a directory that was deleted at the end of the statement.
pub struct Workspace {
    _tmp: TempDir,
    root: PathBuf,
}

impl Workspace {
    pub fn new() -> Self {
        let tmp = tempfile::tempdir().expect("create a temp dir");
        let root = tmp.path().to_path_buf();
        Self { _tmp: tmp, root }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Write `contents` to `name` under the workspace and return its path.
    pub fn write(&self, name: &str, contents: &str) -> PathBuf {
        let path = self.root.join(name);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create parent dirs");
        }
        fs::write(&path, contents).expect("write fixture file");
        path
    }
}

impl Default for Workspace {
    fn default() -> Self {
        Self::new()
    }
}

/// Why a poll gave up.
#[derive(Debug)]
pub enum PollError<E> {
    /// The probe failed; this is not "not yet", it is a failure now.
    Probe(E),
    /// The deadline passed. Carries what was being waited for and how
    /// long, so the failure reads without a rerun.
    Deadline { what: String, waited: Duration },
}

/// The replacement for a sleep before an assertion. `probe` returns
/// `Ok(None)` for "keep waiting", `Ok(Some(value))` for done, and `Err`
/// for a failure that should stop the poll immediately.
pub fn poll_until<T, E, F>(what: &str, timeout: Duration, mut probe: F) -> Result<T, PollError<E>>
where
    F: FnMut() -> Result<Option<T>, E>,
{
    let start = Instant::now();
    loop {
        if let Some(value) = probe().map_err(PollError::Probe)? {
            return Ok(value);
        }
        if start.elapsed() >= timeout {
            return Err(PollError::Deadline {
                what: what.to_string(),
                waited: start.elapsed(),
            });
        }
        std::thread::sleep(Duration::from_millis(20));
    }
}
