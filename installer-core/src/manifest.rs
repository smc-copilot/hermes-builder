use std::path::{Path, PathBuf};

use base64::Engine as _;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use unicode_normalization::UnicodeNormalization;

use crate::error::{ErrorCode, EngineError, KEY_ID, PUBLIC_KEY};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ManifestFile {
    pub path: String,
    pub sha256: String,
    pub size: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RuntimeManifest {
    #[serde(rename = "schemaVersion")]
    pub schema_version: u32,
    #[serde(rename = "installerVersion")]
    pub installer_version: String,
    #[serde(rename = "agentVersion")]
    pub agent_version: String,
    #[serde(rename = "sourceCommit")]
    pub source_commit: String,
    #[serde(rename = "payloadTreeSha256")]
    pub payload_tree_sha256: String,
    #[serde(rename = "uncompressedPayloadBytes")]
    pub uncompressed_payload_bytes: u64,
    #[serde(rename = "venvEstimatedBytes")]
    pub venv_estimated_bytes: u64,
    #[serde(rename = "keyId")]
    pub key_id: String,
    pub files: Vec<ManifestFile>,
}

pub fn canonical_rel(path: &str) -> Result<String, EngineError> {
    let nfc: String = path.replace('\\', "/").nfc().collect();
    if nfc.starts_with('/') || nfc.chars().nth(1) == Some(':') || nfc.split('/').any(|p| p == "..") {
        return Err(EngineError::new(ErrorCode::PathEscapeDenied));
    }
    Ok(nfc)
}

pub fn tree_digest(entries: &[(String, String, u64)]) -> String {
    let mut ordered = entries.to_vec();
    ordered.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));
    let mut buf = Vec::new();
    for (path, digest, size) in ordered {
        buf.extend(path.as_bytes());
        buf.push(0);
        buf.extend(digest.as_bytes());
        buf.push(0);
        buf.extend(size.to_string().as_bytes());
        buf.push(b'\n');
    }
    hex_sha256(&buf)
}

pub fn hex_sha256(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

pub fn verify_manifest_file(root: &Path, manifest_path: &Path) -> Result<RuntimeManifest, EngineError> {
    let expected = root.join("runtime-manifest-v2.json");
    if manifest_path != expected {
        return Err(EngineError::new(ErrorCode::PathEscapeDenied));
    }
    let body = std::fs::read(manifest_path).map_err(|_| EngineError::new(ErrorCode::SignatureInvalid))?;
    let sig_text = std::fs::read_to_string(root.join("runtime-manifest-v2.sig"))
        .map_err(|_| EngineError::new(ErrorCode::SignatureInvalid))?;
    let sig_raw = base64::engine::general_purpose::STANDARD
        .decode(sig_text.trim())
        .map_err(|_| EngineError::new(ErrorCode::SignatureInvalid))?;
    let sig = Signature::from_slice(&sig_raw).map_err(|_| EngineError::new(ErrorCode::SignatureInvalid))?;
    let vk = VerifyingKey::from_bytes(&PUBLIC_KEY).map_err(|_| EngineError::new(ErrorCode::SignatureInvalid))?;
    vk.verify(&body, &sig).map_err(|_| EngineError::new(ErrorCode::SignatureInvalid))?;
    let manifest: RuntimeManifest = serde_json::from_slice(&body).map_err(|_| EngineError::new(ErrorCode::SignatureInvalid))?;
    if manifest.schema_version != 2 || manifest.key_id != KEY_ID {
        return Err(EngineError::new(ErrorCode::SignatureInvalid));
    }
    if manifest.uncompressed_payload_bytes == 0 || manifest.venv_estimated_bytes == 0 {
        return Err(EngineError::new(ErrorCode::BundleIncomplete));
    }
    let sum: u64 = manifest.files.iter().map(|f| f.size).sum();
    if sum != manifest.uncompressed_payload_bytes {
        return Err(EngineError::new(ErrorCode::BundleHashMismatch));
    }
    let entries: Result<Vec<_>, _> = manifest
        .files
        .iter()
        .map(|f| Ok((canonical_rel(&f.path)?, f.sha256.clone(), f.size)))
        .collect();
    let entries = entries?;
    if tree_digest(&entries) != manifest.payload_tree_sha256 {
        return Err(EngineError::new(ErrorCode::BundleHashMismatch));
    }
    for file in &manifest.files {
        let rel = canonical_rel(&file.path)?;
        let full = root.join(rel.replace('/', "\\"));
        if !full.starts_with(root) {
            return Err(EngineError::new(ErrorCode::PathEscapeDenied));
        }
        let bytes = std::fs::read(&full).map_err(|_| EngineError::new(ErrorCode::BundleHashMismatch))?;
        if bytes.len() as u64 != file.size || hex_sha256(&bytes) != file.sha256 {
            return Err(EngineError::new(ErrorCode::BundleHashMismatch));
        }
    }
    Ok(manifest)
}

pub fn resolve_under(root: &Path, rel: &str) -> Result<PathBuf, EngineError> {
    let rel = canonical_rel(rel)?;
    let full = root.join(rel.replace('/', std::path::MAIN_SEPARATOR_STR));
    if !full.starts_with(root) {
        return Err(EngineError::new(ErrorCode::PathEscapeDenied));
    }
    Ok(full)
}
