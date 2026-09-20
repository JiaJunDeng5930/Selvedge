//! Argument declarations own wire fields, requiredness, value rules and typed construction.

use std::marker::PhantomData;

use selvedge_config_model::HarnessConfig;
use selvedge_domain_model::{CommandEnvironmentMode, HistoryNodeId, JsonObject, TaskId};
use serde_json::{Number, Value, json};

use crate::{DEFAULT_BASH_TIMEOUT_MS, HarnessError, MAX_BASH_TIMEOUT_MS, MIN_BASH_TIMEOUT_MS};

pub(super) const MIN_READ_LIMIT: u8 = 1;
pub(super) const MAX_READ_LIMIT: u8 = 100;

pub(super) trait ToolArguments: Sized {
    fn parse(arguments: &JsonObject, config: &HarnessConfig) -> Result<Self, HarnessError>;
    fn schema(config: &HarnessConfig) -> JsonObject;
    fn signature() -> String;
}

trait ArgumentValue {
    type Output;
    fn schema(config: &HarnessConfig) -> Value;
    fn parse(
        name: &str,
        value: &Value,
        config: &HarnessConfig,
    ) -> Result<Self::Output, HarnessError>;
}

trait Parameter {
    type Output;
    const REQUIRED: bool;
    fn schema(config: &HarnessConfig) -> Value;
    fn parse(
        name: &str,
        value: Option<&Value>,
        config: &HarnessConfig,
    ) -> Result<Self::Output, HarnessError>;
}

struct Required<T>(PhantomData<T>);
struct Optional<T>(PhantomData<T>);
struct Defaulted<T>(PhantomData<T>);

impl<T: ArgumentValue> Parameter for Required<T> {
    type Output = T::Output;
    const REQUIRED: bool = true;
    fn schema(config: &HarnessConfig) -> Value {
        T::schema(config)
    }
    fn parse(
        name: &str,
        value: Option<&Value>,
        config: &HarnessConfig,
    ) -> Result<Self::Output, HarnessError> {
        let value = value.ok_or_else(|| {
            HarnessError::invalid_arguments(format!("missing required argument '{name}'"))
        })?;
        T::parse(name, value, config)
    }
}

impl<T: ArgumentValue> Parameter for Optional<T> {
    type Output = Option<T::Output>;
    const REQUIRED: bool = false;
    fn schema(config: &HarnessConfig) -> Value {
        T::schema(config)
    }
    fn parse(
        name: &str,
        value: Option<&Value>,
        config: &HarnessConfig,
    ) -> Result<Self::Output, HarnessError> {
        value.map(|value| T::parse(name, value, config)).transpose()
    }
}

trait DefaultArgument: ArgumentValue {
    fn default_value() -> Self::Output;
}

impl<T: DefaultArgument> Parameter for Defaulted<T> {
    type Output = T::Output;
    const REQUIRED: bool = false;
    fn schema(config: &HarnessConfig) -> Value {
        T::schema(config)
    }
    fn parse(
        name: &str,
        value: Option<&Value>,
        config: &HarnessConfig,
    ) -> Result<Self::Output, HarnessError> {
        value.map_or_else(
            || Ok(T::default_value()),
            |value| T::parse(name, value, config),
        )
    }
}

// This is a finite declaration helper, not a runtime registry. Rust checks that each
// field's parser returns its declared type; all wire metadata follows that parser.
macro_rules! tool_arguments {
    ($name:ident { $($field:ident: $output:ty = $parameter:ty => $description:expr),+ $(,)? } $($validate:expr)?) => {
        #[derive(Clone, Debug, PartialEq, Eq)]
        pub(super) struct $name { $(pub(super) $field: $output),+ }
        impl ToolArguments for $name {
            fn parse(arguments: &JsonObject, config: &HarnessConfig) -> Result<Self, HarnessError> {
                let allowed = [$(stringify!($field)),+];
                for name in arguments.keys() {
                    if !allowed.contains(&name.as_str()) {
                        return Err(HarnessError::invalid_arguments(format!("unexpected argument '{name}'")));
                    }
                }
                let parsed = Self { $($field: <$parameter>::parse(stringify!($field), arguments.get(stringify!($field)), config)?),+ };
                $(($validate)(&parsed)?;)?
                Ok(parsed)
            }
            fn schema(config: &HarnessConfig) -> JsonObject {
                let mut properties = JsonObject::new();
                let mut required: Vec<&str> = Vec::new();
                $(
                    let mut property = <$parameter>::schema(config);
                    property["description"] = Value::String(($description).to_string());
                    properties.insert(stringify!($field).to_owned(), property);
                    if <$parameter>::REQUIRED { required.push(stringify!($field)); }
                )+
                required.sort_unstable();
                json!({"type": "object", "properties": properties, "required": required, "additionalProperties": false})
                    .as_object().expect("schema is an object").clone()
            }
            fn signature() -> String {
                let fields = [$(format!("{}{}", stringify!($field), if <$parameter>::REQUIRED { "" } else { "?" })),+];
                let default = if false $(|| <$parameter>::REQUIRED)+ { "" } else { " = {}" };
                format!("{{{}}}{default}", fields.join(", "))
            }
        }
    };
}

struct NonemptyString;
impl ArgumentValue for NonemptyString {
    type Output = String;
    fn schema(_: &HarnessConfig) -> Value {
        json!({"type": "string"})
    }
    fn parse(name: &str, value: &Value, _: &HarnessConfig) -> Result<String, HarnessError> {
        let value = value.as_str().ok_or_else(|| {
            HarnessError::invalid_arguments(format!("argument '{name}' must be a string"))
        })?;
        if value.trim().is_empty() {
            return Err(HarnessError::invalid_arguments(format!(
                "argument '{name}' must not be empty"
            )));
        }
        Ok(value.to_owned())
    }
}

struct TaskIdentity;
impl ArgumentValue for TaskIdentity {
    type Output = TaskId;
    fn schema(config: &HarnessConfig) -> Value {
        NonemptyString::schema(config)
    }
    fn parse(name: &str, value: &Value, config: &HarnessConfig) -> Result<TaskId, HarnessError> {
        NonemptyString::parse(name, value, config).map(TaskId)
    }
}

struct Integer;
impl ArgumentValue for Integer {
    type Output = i64;
    fn schema(_: &HarnessConfig) -> Value {
        json!({"type": "integer"})
    }
    fn parse(name: &str, value: &Value, _: &HarnessConfig) -> Result<i64, HarnessError> {
        value
            .as_number()
            .and_then(exact_json_integer)
            .ok_or_else(|| {
                HarnessError::invalid_arguments(format!("argument '{name}' must be an integer"))
            })
    }
}

struct HistoryCursor;
impl ArgumentValue for HistoryCursor {
    type Output = HistoryNodeId;
    fn schema(config: &HarnessConfig) -> Value {
        Integer::schema(config)
    }
    fn parse(
        name: &str,
        value: &Value,
        config: &HarnessConfig,
    ) -> Result<HistoryNodeId, HarnessError> {
        Integer::parse(name, value, config).map(HistoryNodeId)
    }
}

// Bounds describe both the JSON Schema and the accepted mathematical integers.
trait IntegerRange {
    type Output;
    fn bounds(config: &HarnessConfig) -> (i64, i64);
    fn convert(value: i64) -> Self::Output;
}
impl<T: IntegerRange> ArgumentValue for T {
    type Output = T::Output;
    fn schema(config: &HarnessConfig) -> Value {
        let (minimum, maximum) = T::bounds(config);
        json!({"type": "integer", "minimum": minimum, "maximum": maximum})
    }
    fn parse(
        name: &str,
        value: &Value,
        config: &HarnessConfig,
    ) -> Result<Self::Output, HarnessError> {
        let value = Integer::parse(name, value, config)?;
        let (minimum, maximum) = T::bounds(config);
        if !(minimum..=maximum).contains(&value) {
            return Err(HarnessError::invalid_arguments(format!(
                "argument '{name}' must be between {minimum} and {maximum}"
            )));
        }
        Ok(T::convert(value))
    }
}
struct ReadLimit;
impl IntegerRange for ReadLimit {
    type Output = u8;
    fn bounds(_: &HarnessConfig) -> (i64, i64) {
        (i64::from(MIN_READ_LIMIT), i64::from(MAX_READ_LIMIT))
    }
    fn convert(value: i64) -> u8 {
        value as u8
    }
}
struct BashTimeout;
impl IntegerRange for BashTimeout {
    type Output = u64;
    fn bounds(_: &HarnessConfig) -> (i64, i64) {
        (MIN_BASH_TIMEOUT_MS, MAX_BASH_TIMEOUT_MS)
    }
    fn convert(value: i64) -> u64 {
        value as u64
    }
}
impl DefaultArgument for BashTimeout {
    fn default_value() -> u64 {
        DEFAULT_BASH_TIMEOUT_MS as u64
    }
}
struct ForkChildCount;
impl IntegerRange for ForkChildCount {
    type Output = usize;
    fn bounds(config: &HarnessConfig) -> (i64, i64) {
        (1, i64::from(config.max_children_per_fork))
    }
    fn convert(value: i64) -> usize {
        value as usize
    }
}
struct EnvironmentMode;
const ENVIRONMENT_MODES: [(&str, CommandEnvironmentMode); 3] = [
    ("shared", CommandEnvironmentMode::Shared),
    ("copy", CommandEnvironmentMode::Copy),
    ("new", CommandEnvironmentMode::New),
];
fn environment_mode_choices() -> String {
    let names = ENVIRONMENT_MODES.map(|(name, _)| name);
    let (last, preceding) = names.split_last().expect("environment has supported modes");
    format!("{}, or {last}", preceding.join(", "))
}
impl ArgumentValue for EnvironmentMode {
    type Output = CommandEnvironmentMode;
    fn schema(_: &HarnessConfig) -> Value {
        json!({"type": "string", "enum": ENVIRONMENT_MODES.map(|(name, _)| name)})
    }
    fn parse(_: &str, value: &Value, _: &HarnessConfig) -> Result<Self::Output, HarnessError> {
        ENVIRONMENT_MODES
            .iter()
            .find(|(name, _)| value.as_str() == Some(*name))
            .map(|(_, mode)| *mode)
            .ok_or_else(|| {
                HarnessError::invalid_arguments(format!(
                    "environment must be {}",
                    environment_mode_choices()
                ))
            })
    }
}
impl DefaultArgument for EnvironmentMode {
    fn default_value() -> CommandEnvironmentMode {
        CommandEnvironmentMode::Shared
    }
}
struct InitialMessages;
impl ArgumentValue for InitialMessages {
    type Output = Vec<String>;
    fn schema(config: &HarnessConfig) -> Value {
        let (minimum, maximum) = ForkChildCount::bounds(config);
        json!({"type": "array", "items": {"type": "string"}, "minItems": minimum, "maxItems": maximum})
    }
    fn parse(name: &str, value: &Value, _: &HarnessConfig) -> Result<Self::Output, HarnessError> {
        let invalid = || {
            HarnessError::invalid_arguments(format!(
                "argument '{name}' must be an array of strings"
            ))
        };
        value
            .as_array()
            .ok_or_else(invalid)?
            .iter()
            .map(|value| {
                let value = value.as_str().ok_or_else(invalid)?;
                if value.trim().is_empty() {
                    return Err(HarnessError::invalid_arguments(format!(
                        "argument '{name}' entries must not be empty"
                    )));
                }
                Ok(value.to_owned())
            })
            .collect()
    }
}

// Unlike model source/message strings, a file body may be empty. Keep the command's
// existing missing/type diagnostic while declaring that the field is required.
struct FileContent;
impl Parameter for FileContent {
    type Output = String;
    const REQUIRED: bool = true;
    fn schema(_: &HarnessConfig) -> Value {
        json!({"type": "string"})
    }
    fn parse(_: &str, value: Option<&Value>, _: &HarnessConfig) -> Result<String, HarnessError> {
        value
            .and_then(Value::as_str)
            .map(str::to_owned)
            .ok_or_else(|| HarnessError::invalid_arguments("content must be a string"))
    }
}

tool_arguments!(ReadTaskInvocation {
    task_id: Option<TaskId> = Optional<TaskIdentity> => "Task to read; omit it to read the calling task.",
    after_node_id: Option<HistoryNodeId> = Optional<HistoryCursor> => "Return history nodes after this node ID.",
    limit: Option<u8> = Optional<ReadLimit> => format!("Maximum history nodes to return, from {MIN_READ_LIMIT} through {MAX_READ_LIMIT}."),
});
tool_arguments!(ForkTaskInvocation {
    environment: CommandEnvironmentMode = Defaulted<EnvironmentMode> => "Command environment inheritance: shared (default), copy, or new.",
    child_count: usize = Required<ForkChildCount> => "Number of child task branches to create.",
    messages: Option<Vec<String>> = Optional<InitialMessages> => "Optional initial messages aligned by child branch number.",
} |parsed: &ForkTaskInvocation| {
    if parsed.messages.as_ref().is_some_and(|messages| messages.len() != parsed.child_count) {
        Err(HarnessError::invalid_arguments("argument 'messages' length must equal 'child_count'"))
    } else { Ok(()) }
});
tool_arguments!(SendMessageToTaskInvocation {
    task_id: TaskId = Required<TaskIdentity> => "Task that should receive the message.",
    message: String = Required<NonemptyString> => "Message to send to the task.",
});
tool_arguments!(ArchiveTaskInvocation {
    task_id: TaskId = Required<TaskIdentity> => "Task to archive.",
});
tool_arguments!(OptionalTaskTarget {
    task_id: Option<TaskId> = Optional<TaskIdentity> => "Task to change; omit it to use the calling task.",
});
tool_arguments!(ExecCmdArguments {
    code: String = Required<NonemptyString> => "JavaScript source, including top-level await.",
});
tool_arguments!(BashInvocation {
    command: String = Required<NonemptyString> => "Bash command to run.",
    timeout_ms: u64 = Defaulted<BashTimeout> => format!("Timeout in milliseconds; defaults to {DEFAULT_BASH_TIMEOUT_MS}, from {MIN_BASH_TIMEOUT_MS} through {MAX_BASH_TIMEOUT_MS}."),
});
tool_arguments!(WriteFileArguments {
    path: String = Required<NonemptyString> => "Path of the file to write.",
    content: String = FileContent => "UTF-8 file content.",
});

// JSON Schema integer semantics are mathematical, so decimal and exponent
// spellings must be evaluated from the exact token instead of through f64.
fn exact_json_integer(number: &Number) -> Option<i64> {
    let source = number.to_string();
    let (negative, unsigned) = match source.strip_prefix('-') {
        Some(unsigned) => (true, unsigned),
        None => (false, source.as_str()),
    };
    let exponent_start = unsigned.find(['e', 'E']);
    let (mantissa, exponent) = exponent_start.map_or((unsigned, None), |index| {
        (&unsigned[..index], Some(&unsigned[index + 1..]))
    });
    let (whole, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
    let mut digits = String::with_capacity(whole.len() + fraction.len());
    digits.push_str(whole);
    digits.push_str(fraction);

    if digits.bytes().all(|digit| digit == b'0') {
        return Some(0);
    }

    let exponent = match exponent {
        Some(exponent) => exponent.parse::<i64>().ok()?,
        None => 0,
    };
    let fraction_len = i64::try_from(fraction.len()).ok()?;
    let scale = exponent.checked_sub(fraction_len)?;
    let coefficient_end = if scale < 0 {
        let discarded_len = scale.checked_neg()?;
        if discarded_len > i64::try_from(digits.len()).ok()? {
            return None;
        }
        let coefficient_end = digits.len() - usize::try_from(discarded_len).ok()?;
        if digits.as_bytes()[coefficient_end..]
            .iter()
            .any(|digit| *digit != b'0')
        {
            return None;
        }
        coefficient_end
    } else {
        digits.len()
    };

    // A nonzero i64 cannot contain more than 19 decimal places. This bound
    // also keeps enormous JSON exponents from turning into long loops.
    if scale > 18 {
        return None;
    }
    let limit = if negative {
        (i64::MAX as u64) + 1
    } else {
        i64::MAX as u64
    };
    let mut magnitude = 0_u64;
    for digit in digits.as_bytes()[..coefficient_end].iter().copied() {
        let digit = u64::from(digit.checked_sub(b'0')?);
        if digit > 9 {
            return None;
        }
        magnitude = magnitude.checked_mul(10)?.checked_add(digit)?;
        if magnitude > limit {
            return None;
        }
    }
    for _ in 0..usize::try_from(scale).unwrap_or(0) {
        magnitude = magnitude.checked_mul(10)?;
        if magnitude > limit {
            return None;
        }
    }

    if negative && magnitude == (i64::MAX as u64) + 1 {
        Some(i64::MIN)
    } else {
        let magnitude = i64::try_from(magnitude).ok()?;
        Some(if negative { -magnitude } else { magnitude })
    }
}
