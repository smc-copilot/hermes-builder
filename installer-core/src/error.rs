use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ErrorCode {
    SourceRefMismatch,
    SourceDirty,
    AgentVersionChangeDenied,
    BundleIncomplete,
    BundleHashMismatch,
    ManifestSigningKeyMissing,
    SignatureInvalid,
    ReleaseIdentityMismatch,
    PathEscapeDenied,
    MsiInstallFailed,
    InstallIdentityDenied,
    DiskSpaceInsufficient,
    RuntimeInUse,
    InstallBusy,
    RebootRequired,
    EngineInterrupted,
    UvSyncFailed,
    HermesCliMissing,
    HermesCliVerifyFailed,
    RuntimeRollbackFailed,
    RuntimeInitializationFailed,
    ReceiptCommitFailed,
    SkillOwnershipConflict,
    DiagnosticsUnavailable,
    ExportTargetNotEmpty,
    StateTransitionDenied,
    OperationSchemaUnsupported,
    PayloadRepairRequired,
    MigrationBlocked,
    GoldenConsumerBlocked,
}

impl ErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::SourceRefMismatch => "SOURCE_REF_MISMATCH",
            Self::SourceDirty => "SOURCE_DIRTY",
            Self::AgentVersionChangeDenied => "AGENT_VERSION_CHANGE_DENIED",
            Self::BundleIncomplete => "BUNDLE_INCOMPLETE",
            Self::BundleHashMismatch => "BUNDLE_HASH_MISMATCH",
            Self::ManifestSigningKeyMissing => "MANIFEST_SIGNING_KEY_MISSING",
            Self::SignatureInvalid => "SIGNATURE_INVALID",
            Self::ReleaseIdentityMismatch => "RELEASE_IDENTITY_MISMATCH",
            Self::PathEscapeDenied => "PATH_ESCAPE_DENIED",
            Self::MsiInstallFailed => "MSI_INSTALL_FAILED",
            Self::InstallIdentityDenied => "INSTALL_IDENTITY_DENIED",
            Self::DiskSpaceInsufficient => "DISK_SPACE_INSUFFICIENT",
            Self::RuntimeInUse => "RUNTIME_IN_USE",
            Self::InstallBusy => "INSTALL_BUSY",
            Self::RebootRequired => "REBOOT_REQUIRED",
            Self::EngineInterrupted => "ENGINE_INTERRUPTED",
            Self::UvSyncFailed => "UV_SYNC_FAILED",
            Self::HermesCliMissing => "HERMES_CLI_MISSING",
            Self::HermesCliVerifyFailed => "HERMES_CLI_VERIFY_FAILED",
            Self::RuntimeRollbackFailed => "RUNTIME_ROLLBACK_FAILED",
            Self::RuntimeInitializationFailed => "RUNTIME_INITIALIZATION_FAILED",
            Self::ReceiptCommitFailed => "RECEIPT_COMMIT_FAILED",
            Self::SkillOwnershipConflict => "SKILL_OWNERSHIP_CONFLICT",
            Self::DiagnosticsUnavailable => "DIAGNOSTICS_UNAVAILABLE",
            Self::ExportTargetNotEmpty => "EXPORT_TARGET_NOT_EMPTY",
            Self::StateTransitionDenied => "STATE_TRANSITION_DENIED",
            Self::OperationSchemaUnsupported => "OPERATION_SCHEMA_UNSUPPORTED",
            Self::PayloadRepairRequired => "PAYLOAD_REPAIR_REQUIRED",
            Self::MigrationBlocked => "MIGRATION_BLOCKED",
            Self::GoldenConsumerBlocked => "GOLDEN_CONSUMER_BLOCKED",
        }
    }
}

#[derive(Debug)]
pub struct EngineError {
    pub code: ErrorCode,
    pub operation_id: String,
    pub diagnostics_dir: String,
}

impl EngineError {
    pub fn new(code: ErrorCode) -> Self {
        Self { code, operation_id: String::new(), diagnostics_dir: String::new() }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RuntimeState {
    Ready,
    Absent,
    PayloadInstalled,
    RepairRequired,
    Interrupted,
    Initializing,
    PayloadInstalledRebootRequired,
}

impl RuntimeState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Ready => "READY",
            Self::Absent => "ABSENT",
            Self::PayloadInstalled => "PAYLOAD_INSTALLED",
            Self::RepairRequired => "REPAIR_REQUIRED",
            Self::Interrupted => "INTERRUPTED",
            Self::Initializing => "INITIALIZING",
            Self::PayloadInstalledRebootRequired => "PAYLOAD_INSTALLED_REBOOT_REQUIRED",
        }
    }

    pub fn status_exit(self) -> i32 {
        match self {
            Self::Ready => 0,
            Self::Absent => 20,
            Self::PayloadInstalled => 21,
            Self::RepairRequired => 22,
            Self::Interrupted => 23,
            Self::Initializing => 24,
            Self::PayloadInstalledRebootRequired => 25,
        }
    }
}

pub const COMMIT_ORDER: &[&str] = &[
    "UV_SYNC",
    "IMPORT_VERIFY",
    "CLI_VERIFY_VENV",
    "SKILLS_MERGE",
    "ENV_APPLY",
    "CLI_STAGE_BIN",
    "CLI_VERIFY_BIN",
    "RECEIPT_COMMIT",
];

pub const AGENT_VERSION: &str = "0.21.0";
pub const INSTALLER_VERSION: &str = "2.0.0";
pub const SOURCE_COMMIT: &str = "041b6985a00d01b54f830c1607dd370007a306bf";
pub const KEY_ID: &str = "e6199f4b558ab9c4";
pub const PUBLIC_KEY: [u8; 32] = [
    0x77, 0xba, 0xb4, 0x65, 0xc8, 0xde, 0x1e, 0x57, 0xe3, 0x73, 0x8c, 0xb6, 0xca, 0x6f, 0xd5, 0x26,
    0x37, 0x8d, 0x65, 0x89, 0xf7, 0x72, 0xe9, 0x14, 0x62, 0x6f, 0x54, 0x17, 0x90, 0x9f, 0x8d, 0xe1,
];
