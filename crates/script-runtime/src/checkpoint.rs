use crate::{ScriptCheckpoint, ScriptRuntimeError};

// Includes the runtime ABI, external callback table, engine and target. There is
// deliberately no fallback parser for previous checkpoint formats.
fn header() -> Vec<u8> {
    format!(
        "selvedge-script-checkpoint:1\nv8:{}\ntarget:{}-{}\n\0",
        v8::V8::get_version(),
        std::env::consts::ARCH,
        std::env::consts::OS,
    )
    .into_bytes()
}

pub(crate) fn encode(blob: v8::StartupData) -> ScriptCheckpoint {
    let mut bytes = header();
    bytes.extend_from_slice(&(blob.len() as u64).to_le_bytes());
    bytes.extend_from_slice(&checksum(&blob).to_le_bytes());
    bytes.extend_from_slice(&blob);
    ScriptCheckpoint(bytes)
}

pub(crate) fn decode(checkpoint: ScriptCheckpoint) -> Result<v8::StartupData, ScriptRuntimeError> {
    let header = header();
    let bytes = checkpoint.0;
    let Some(body) = bytes.strip_prefix(header.as_slice()) else {
        return Err(invalid("format, engine version, or target does not match"));
    };
    let Some((length, body)) = body.split_first_chunk::<8>() else {
        return Err(invalid("truncated length"));
    };
    let Some((hash, blob)) = body.split_first_chunk::<8>() else {
        return Err(invalid("truncated checksum"));
    };
    if u64::from_le_bytes(*length) != blob.len() as u64 || blob.len() < 128 {
        return Err(invalid("invalid snapshot length"));
    }
    if u64::from_le_bytes(*hash) != checksum(blob) {
        return Err(invalid("snapshot checksum does not match"));
    }
    let startup = v8::StartupData::from(blob.to_vec());
    if !startup.is_valid() {
        return Err(invalid("V8 rejected the snapshot"));
    }
    Ok(startup)
}

fn invalid(message: &str) -> ScriptRuntimeError {
    ScriptRuntimeError::InvalidCheckpoint(message.to_owned())
}

fn checksum(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf2_9ce4_8422_2325, |hash, byte| {
        (hash ^ u64::from(*byte)).wrapping_mul(0x100_0000_01b3)
    })
}
